import Foundation
import GCPAPISync
import SwiftUI
import Testing

@testable import GCPAPISyncApp

/// Hands out queued results, one per load, and records the ranges asked for.
private actor Results {
    var queue: [Result<HealthHistory, Problem>]
    var requestedDays: [Int] = []

    init(_ queue: [Result<HealthHistory, Problem>]) {
        self.queue = queue
    }

    func next(days: Int) throws -> HealthHistory {
        requestedDays.append(days)
        return try queue.removeFirst().get()
    }
}

@Suite struct HealthModelTests {
    private let end = GarminDate.day("2026-10-28")

    @Test func loadsTheWeekEndingToday() async {
        let model = HealthModel(
            today: { .day("2026-10-28") },
            fetch: { end, days in .sample(endingOn: end, days: days) })
        #expect(model.phase == .loading)
        await model.load()
        #expect(model.phase == .loaded(.sample(endingOn: end)))
        #expect(model.histories[7] == .sample(endingOn: end))
        #expect(model.lastUpdated != nil)
        #expect(model.refreshProblem == nil)
    }

    @Test func aFirstFailureIsShownInPlace() async {
        let model = HealthModel { _, _ in throw Problem.offline }
        await model.load()
        #expect(model.phase == .failed(.offline))
    }

    @Test func aFailedRefreshKeepsTheData() async {
        let results = Results([
            .success(.sample(endingOn: end)), .failure(.rateLimited),
            .success(.sample(endingOn: end)),
        ])
        let model = HealthModel { _, days in try await results.next(days: days) }
        await model.load()
        await model.load()
        #expect(model.phase == .loaded(.sample(endingOn: end)))
        #expect(model.refreshProblem == .rateLimited)
        await model.load()
        #expect(model.refreshProblem == nil)
    }

    @Test func cancellationIsNoFailure() async {
        let model = HealthModel { _, _ in throw CancellationError() }
        await model.load()
        #expect(model.phase == .loading)
        await model.loadHistory(days: 30)
        #expect(model.historyProblems.isEmpty)
    }

    @Test func longerRangesAreLoadedOnceAndRefreshedWithTheWeek() async {
        let month = HealthHistory.sample(endingOn: end, days: 30)
        let results = Results([
            .success(.sample(endingOn: end)), .success(month), .success(.sample(endingOn: end)),
            .success(month),
        ])
        let model = HealthModel { _, days in try await results.next(days: days) }
        await model.load()
        await model.loadHistory(days: 30)
        await model.loadHistory(days: 30)
        await model.loadHistory(days: 7)
        #expect(model.histories[30] == month)
        #expect(await results.requestedDays == [7, 30])
        // A refresh drops the longer ranges, so they are fetched again when shown.
        await model.load()
        #expect(model.histories[30] == nil)
        await model.loadHistory(days: 30)
        #expect(await results.requestedDays == [7, 30, 7, 30])
    }

    @Test func aFailedRangeCanBeRetried() async {
        let results = Results([.failure(.timedOut), .success(.sample(endingOn: end, days: 90))])
        let model = HealthModel { _, days in try await results.next(days: days) }
        await model.loadHistory(days: 90)
        #expect(model.historyProblems[90] == .timedOut)
        await model.loadHistory(days: 90)
        #expect(model.historyProblems[90] == nil)
        #expect(model.histories[90]?.days.count == 90)
    }

    @Test func garminErrorsBecomeProblems() async throws {
        let rejected = StubTransport { request in
            request.path == tokenPath ? (200, "token") : (401, "")
        }
        let model = HealthModel(client: try client(rejected))
        await model.load()
        #expect(model.phase == .failed(.keyRejected))
    }
}

@Suite struct MetricTests {
    private let history = HealthHistory.sample(endingOn: .day("2026-10-28"))

    @Test(arguments: Metric.allCases)
    func everyMetricIsPresentable(metric: Metric) {
        #expect(!metric.title.isEmpty)
        #expect(!metric.symbol.isEmpty)
        #expect(!metric.explanation.isEmpty)
        let summary = metric.summary(of: history)
        #expect(summary.value != "–")
        #expect(!summary.detail.isEmpty)
        let day = history.days[0]
        #expect(metric.hasValue(day))
        #expect(metric.summary(of: day).value == metric.value(of: day))
        let empty = DayHealth(date: day.date)
        #expect(!metric.hasValue(empty))
        #expect(metric.value(of: empty) == "–")
        #expect(metric.detail(of: empty) == nil)
    }

    @Test func summaries() {
        var days = (0..<2).map { DayHealth(date: GarminDate.day("2026-10-27").adding(days: $0)) }
        days[0].steps = 12_000
        days[0].stepGoal = 10_000
        days[1].steps = 4000
        days[1].stepGoal = 10_000
        days[0].intensityMinutes = 100
        days[1].intensityMinutes = 100
        let pair = HealthHistory(days: days)
        #expect(Metric.steps.summary(of: pair).value == 8000.formatted())
        #expect(Metric.steps.summary(of: pair).detail == String(localized: "1 of 2 days at goal"))
        // 200 minutes in two days is 700 per week.
        #expect(Metric.intensityMinutes.summary(of: pair).value == 700.formatted())
        #expect(Metric.intensityMinutes.summary(of: HealthHistory(days: [])).value == "0")
        #expect(Metric.sleep.summary(of: pair).detail == String(localized: "No sleep score"))
    }

    @Test(arguments: HistoryRange.allCases)
    func ranges(range: HistoryRange) {
        #expect(range.days == range.rawValue)
        #expect(!range.label.isEmpty)
        #expect(range.caption.contains("\(range.days)"))
    }
}

@Suite struct ProblemTests {
    @Test(arguments: [
        Problem.emptyKey, .keyRejected, .offline, .timedOut, .rateLimited, .garminUnavailable,
        .keychain,
        .unexpected("detail"),
    ])
    func everyProblemIsExplained(problem: Problem) {
        #expect(!problem.title.isEmpty)
        #expect(!problem.message.isEmpty)
        #expect(!problem.symbol.isEmpty)
        #expect(Problem(problem) == problem)
    }

    @Test func classification() async {
        func failure(
            _ respond: @escaping @Sendable (HTTPRequest) -> (status: Int, body: String)
        ) async -> Problem? {
            do {
                _ = try await client(StubTransport(respond)).getAccessToken()
                return nil
            } catch {
                return Problem(error)
            }
        }
        #expect(await failure { _ in (429, "") } == .rateLimited)
        #expect(await failure { _ in (500, "") } == .garminUnavailable)
        #expect(
            await failure { _ in (418, "") } == .unexpected("POST \(tokenPath) returned HTTP 418"))
        #expect(Problem(KeychainError(status: -25_300)) == .keychain)
        #expect(Problem(CocoaError(.fileNoSuchFile)) != .keychain)
        #expect(Problem(TransportProblem()) == .unexpected("transport"))
    }

    private struct TransportProblem: LocalizedError {
        var errorDescription: String? { "transport" }
    }
}

@Suite struct FormatTests {
    @Test func durations() {
        #expect(Format.duration(seconds: nil) == "–")
        #expect(
            Format.duration(seconds: 0)
                == Duration.seconds(0).formatted(
                    .units(allowed: [.hours, .minutes], width: .narrow)))
        #expect(Format.number(nil) == "–")
        #expect(Format.number(1234) == 1234.formatted())
    }

    @Test(arguments: ["BALANCED", "UNBALANCED", "LOW", "POOR"])
    func hrvStatuses(status: String) {
        #expect(Format.hrvStatus(status) != nil)
    }

    @Test func unknownHRVStatus() {
        #expect(Format.hrvStatus("NONE") == nil)
        #expect(Format.hrvStatus(nil) == nil)
    }

    @Test(
        arguments: [(nil, "–"), (10, "Resting"), (40, "Low"), (60, "Medium"), (90, "High")]
            as [(Int?, String)])
    func stressBands(level: Int?, label: String) {
        #expect(Format.stressLabel(level) == String(localized: String.LocalizationValue(label)))
        if let level {
            _ = Format.stressColor(level)
        }
    }
}
