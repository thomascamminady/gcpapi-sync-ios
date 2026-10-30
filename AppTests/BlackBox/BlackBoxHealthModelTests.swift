import Foundation
import GCPAPISync
import Testing

@testable import GCPAPISyncApp

private typealias Script = BlackBoxScript<HealthHistory>

/// The phase in a word, for comparisons.
private func describe(_ phase: HealthModel.Phase) -> String {
    switch phase {
    case .loading: "loading"
    case .loaded: "loaded"
    case .failed: "failed"
    }
}

/// The history a loaded phase shows.
private func shown(_ phase: HealthModel.Phase) -> HealthHistory? {
    if case .loaded(let history) = phase { history } else { nil }
}

@Suite("Health model")
struct BlackBoxHealthModelTests {
    private let today = GarminDate.day("2026-10-30")
    private let first = HealthHistory.sample(endingOn: .day("2026-10-30"))
    private let second = HealthHistory.sample(endingOn: .day("2026-10-29"))

    private func model(_ script: Script, clock: BlackBoxClock) -> HealthModel {
        let today = today
        return HealthModel(
            today: { today }, now: { clock.now },
            fetch: { date, days in try await script.play("\(date) \(days)") })
    }

    @Test("A new model is loading and has nothing yet")
    func initial() {
        let model = model(Script([], otherwise: .value(first)), clock: BlackBoxClock())
        #expect(describe(model.phase) == "loading")
        #expect(model.lastUpdated == nil)
        #expect(model.refreshProblem == nil)
        #expect(model.histories.isEmpty)
        #expect(model.historyProblems.isEmpty)
    }

    @Test("Loading fetches the dashboard's week ending today")
    func load() async {
        let script = Script([], otherwise: .value(first))
        let clock = BlackBoxClock()
        let model = model(script, clock: clock)
        await model.load()
        #expect(shown(model.phase) == first)
        #expect(model.lastUpdated == clock.now)
        #expect(model.refreshProblem == nil)
        #expect(await script.calls == ["\(today) \(HealthModel.dashboardDays)"])
        #expect(HealthModel.dashboardDays == 7)
    }

    @Test("A failed first load fails in place, and a retry recovers")
    func firstFailure() async {
        let script = Script([.failure(BlackBoxError(code: 1))], otherwise: .value(first))
        let model = model(script, clock: BlackBoxClock())
        await model.load()
        #expect(describe(model.phase) == "failed")
        #expect(model.lastUpdated == nil)
        await model.load()
        #expect(shown(model.phase) == first)
        #expect(model.refreshProblem == nil)
    }

    @Test("A failed refresh keeps the older data and says so")
    func refreshFailure() async {
        let script = Script(
            [.value(first), .failure(BlackBoxError(code: 2)), .value(second)],
            otherwise: .value(second))
        let clock = BlackBoxClock()
        let model = model(script, clock: clock)
        await model.load()
        let loadedAt = clock.now
        clock.advance(3600)
        await model.load()
        #expect(shown(model.phase) == first)
        #expect(model.refreshProblem != nil)
        #expect(model.lastUpdated == loadedAt)
        clock.advance(60)
        await model.load()
        #expect(shown(model.phase) == second)
        #expect(model.refreshProblem == nil)
        #expect(model.lastUpdated == clock.now)
    }

    @Test("A cancelled refresh is no failure")
    func cancelledRefresh() async {
        let script = Script([.value(first), .cancellation], otherwise: .value(second))
        let model = model(script, clock: BlackBoxClock())
        await model.load()
        await model.load()
        #expect(shown(model.phase) == first)
        #expect(model.refreshProblem == nil)
    }

    @Test("A cancelled first load is no failure")
    func cancelledFirstLoad() async {
        let model = model(Script([.cancellation], otherwise: .value(first)), clock: BlackBoxClock())
        await model.load()
        #expect(describe(model.phase) != "failed")
        #expect(model.refreshProblem == nil)
    }

    @Test("Cancelling the task that loads leaves no failure behind")
    func cancelledTask() async {
        let first = first
        let model = HealthModel(
            today: { .day("2026-10-30") },
            fetch: { _, _ in
                try await Task.sleep(for: .seconds(30))
                return first
            })
        let task = Task { await model.load() }
        try? await Task.sleep(for: .milliseconds(50))
        task.cancel()
        await task.value
        #expect(describe(model.phase) != "failed")
        #expect(model.refreshProblem == nil)
    }

    @Test("Loading if needed: only when the week is older than the maximum age")
    func loadIfNeeded() async {
        let script = Script([], otherwise: .value(first))
        let clock = BlackBoxClock()
        let model = model(script, clock: clock)
        await model.loadIfNeeded()
        #expect(await script.count == 1)
        await model.loadIfNeeded()
        clock.advance(10 * 60)
        await model.loadIfNeeded()
        #expect(await script.count == 1)
        clock.advance(6 * 60)
        await model.loadIfNeeded()
        #expect(await script.count == 2)
        clock.advance(30)
        await model.loadIfNeeded(maxAge: 60)
        #expect(await script.count == 2)
        clock.advance(31)
        await model.loadIfNeeded(maxAge: 60)
        #expect(await script.count == 3)
    }

    @Test("Loading if needed retries after a failure")
    func loadIfNeededAfterFailure() async {
        let script = Script([.failure(BlackBoxError(code: 3))], otherwise: .value(first))
        let model = model(script, clock: BlackBoxClock())
        await model.loadIfNeeded()
        #expect(describe(model.phase) == "failed")
        await model.loadIfNeeded()
        #expect(await script.count == 2)
        #expect(shown(model.phase) == first)
    }

    @Test("Histories are fetched once per length")
    func loadHistory() async {
        let script = Script([], otherwise: .value(second))
        let model = model(script, clock: BlackBoxClock())
        await model.loadHistory(days: 30)
        await model.loadHistory(days: 30)
        await model.loadHistory(days: 90)
        #expect(model.histories[30] == second)
        #expect(model.histories[90] == second)
        #expect(model.historyProblems.isEmpty)
        #expect(await script.calls == ["\(today) 30", "\(today) 90"])
    }

    @Test("A failed history is remembered, retried, and forgotten once fetched")
    func historyFailure() async {
        let script = Script([.failure(BlackBoxError(code: 4))], otherwise: .value(second))
        let model = model(script, clock: BlackBoxClock())
        await model.loadHistory(days: 30)
        #expect(model.histories[30] == nil)
        #expect(model.historyProblems[30] != nil)
        await model.loadHistory(days: 30)
        #expect(model.histories[30] == second)
        #expect(model.historyProblems[30] == nil)
        #expect(await script.count == 2)
    }

    @Test("Loading the week leaves the histories alone")
    func independent() async {
        let script = Script([.value(second)], otherwise: .failure(BlackBoxError(code: 5)))
        let model = model(script, clock: BlackBoxClock())
        await model.loadHistory(days: 90)
        await model.load()
        #expect(model.histories[90] == second)
        #expect(describe(model.phase) == "failed")
    }
}
