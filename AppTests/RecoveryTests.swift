import Foundation
import GCPAPISync
import Testing

@testable import GCPAPISyncApp

/// 120 days: every fourth day is hard (load 200), every eighth (shifted) a rest day, the
/// others easy (load 50), and `hrv` gives each day's HRV from its index.
private func scenario(hrv: (Int) -> Int?) -> (HealthHistory, [TrainingLoad.Day]) {
    let first = GarminDate.day("2026-06-01")
    let indices = 0..<120
    let loads = indices.map { index in
        let load: Double =
            if index.isMultiple(of: 4) {
                200
            } else if index % 8 == 2 {
                0
            } else {
                50
            }
        return TrainingLoad.Day(
            date: first.adding(days: index), load: load, fitness: 0, fatigue: 0)
    }
    let days = indices.map { index in
        var day = DayHealth(date: first.adding(days: index))
        day.hrv = hrv(index)
        return day
    }
    return (HealthHistory(days: days), loads)
}

@Suite struct RecoveryResponseTests {
    @Test func findsTheDipAfterHardDays() throws {
        // HRV is 60 ms, and 54 ms (10% lower) the morning after every hard day.
        let (history, loads) = scenario { $0 % 4 == 1 ? 54 : 60 }
        let response = RecoveryResponse(history: history, loads: loads)
        #expect(response.threshold == 200)
        #expect(response.hardDays == 30)
        #expect(response.restDays == 15)
        #expect(response.isSufficient)
        let hrv = try #require(response.curves.first { $0.metric == .hrv })
        #expect(response.headline == hrv)
        let peak = try #require(hrv.peak)
        #expect(peak.lag == 1)
        #expect(abs(peak.mean + 10) < 1e-9)
        #expect(peak.margin < 1e-9)
        #expect(peak.isClear)
        #expect(hrv.hard.first { $0.lag == -1 }?.mean == 0)
        #expect(hrv.recoveredAfter == 2)
        #expect(hrv.sentence.contains(OverviewMetric.hrv.title))
        #expect(hrv.sentence.contains(Format.days(2)))
        // Rest days are followed by a hard day two days later.
        #expect(abs((hrv.rest.first { $0.lag == 3 }?.mean ?? 0) + 10) < 1e-9)
    }

    @Test func noiseIsNoClearChange() throws {
        // The mornings after hard days alternate between 10% above and below the usual 60 ms.
        let (history, loads) = scenario { index in
            index % 4 == 1 ? (index % 8 == 1 ? 66 : 54) : 60
        }
        let hrv = try #require(
            RecoveryResponse(history: history, loads: loads).curves.first { $0.metric == .hrv })
        let peak = try #require(hrv.peak)
        #expect(!peak.isClear)
        #expect(hrv.recoveredAfter == nil)
        #expect(
            hrv.sentence
                == String(
                    localized: "No clear change in \(OverviewMetric.hrv.title) after hard training."
                ))
    }

    @Test func aChangeThatLastsIsNotRecovered() throws {
        // One hard day in ten, three easy days after it, then rest; HRV stays 10% low for the
        // three days after every hard day.
        let first = GarminDate.day("2026-06-01")
        let loads = (0..<150).map { index in
            let phase = index % 10
            return TrainingLoad.Day(
                date: first.adding(days: index), load: phase == 0 ? 200 : phase < 4 ? 50 : 0,
                fitness: 0, fatigue: 0)
        }
        let days = (0..<150).map { index in
            var day = DayHealth(date: first.adding(days: index))
            day.hrv = (1...3).contains(index % 10) ? 54 : 60
            return day
        }
        let hrv = try #require(
            RecoveryResponse(history: HealthHistory(days: days), loads: loads).curves.first {
                $0.metric == .hrv
            })
        #expect(hrv.peak?.isClear == true)
        let lowAfterwards = hrv.hard.filter { $0.lag > 0 }.allSatisfy(\.isClear)
        #expect(lowAfterwards)
        #expect(hrv.recoveredAfter == nil)
    }

    @Test func missingDataSaysSo() throws {
        let (history, loads) = scenario { _ in nil }
        let response = RecoveryResponse(history: history, loads: loads)
        let stress = try #require(response.curves.first { $0.metric == .stress })
        #expect(stress.peak == nil)
        #expect(stress.hard.allSatisfy { $0.events < 1 })
        #expect(stress.sentence.contains(OverviewMetric.stress.title))
        #expect(response.headline?.metric == .hrv)
    }

    @Test func fewHardDaysAreNotEnough() {
        let first = GarminDate.day("2026-06-01")
        let loads = (0..<40).map { index in
            TrainingLoad.Day(
                date: first.adding(days: index), load: index == 30 ? 300 : 0, fitness: 0,
                fatigue: 0)
        }
        let response = RecoveryResponse(history: HealthHistory(days: []), loads: loads)
        #expect(response.hardDays == 1)
        #expect(!response.isSufficient)
        let idle = RecoveryResponse(history: HealthHistory(days: []), loads: [])
        #expect(idle.threshold == nil)
        #expect(idle.hardDays == 0)
    }

    @Test func medians() {
        #expect(RecoveryResponse.median([3, 1, 2]) == 2)
        #expect(RecoveryResponse.median([4, 1, 3, 2]) == 2.5)
        #expect(RecoveryResponse.median([]) == nil)
    }

    @Test func theDemoRespondsToHardTraining() throws {
        let end = GarminDate.day("2026-10-29")
        let data = TrainingData.sample(endingOn: end)
        let response = RecoveryResponse(
            history: .sample(endingOn: end, days: data.loadHistory.count),
            loads: data.loadHistory)
        #expect(response.isSufficient)
        let hrv = try #require(response.curves.first { $0.metric == .hrv })
        #expect(hrv.peak?.lag == 1)
        #expect(hrv.peak?.isClear == true)
        #expect((hrv.peak?.mean ?? 0) < 0)
    }

    @Test func chartLabels() {
        #expect(RecoveryChart.label(lag: 2) == "+2")
        #expect(!RecoveryChart.label(lag: -1).isEmpty)
        #expect(!RecoveryChart.label(lag: 0).isEmpty)
    }
}

@Suite struct RecoveryModelTests {
    private let end = GarminDate.day("2026-10-29")

    @Test func recoveryFollowsTheTrainingData() async {
        let sample = TrainingData.sample(endingOn: end)
        let model = TrainingModel(
            today: { end }, fetch: { _ in sample },
            fetchHealth: { end, days in .sample(endingOn: end, days: days) })
        #expect(model.recovery == .loading)
        await model.load()
        guard case .loaded(let response) = model.recovery else {
            Issue.record("no recovery response")
            return
        }
        #expect(response.isSufficient)
    }

    @Test func aFailedRecoveryKeepsTheOlderOne() async {
        let sample = TrainingData.sample(endingOn: end)
        let health = HealthResults([
            .success(.sample(endingOn: end, days: 210)), .failure(.offline),
        ])
        let model = TrainingModel(
            today: { end }, fetch: { _ in sample },
            fetchHealth: { _, _ in try await health.next() })
        await model.load()
        await model.load()
        guard case .loaded = model.recovery else {
            Issue.record("the older response was dropped")
            return
        }
        let failing = TrainingModel(
            today: { end }, fetch: { _ in sample }, fetchHealth: { _, _ in throw Problem.offline })
        await failing.load()
        #expect(failing.recovery == .failed(.offline))
        let cancelled = TrainingModel(
            today: { end }, fetch: { _ in sample },
            fetchHealth: { _, _ in throw CancellationError() })
        await cancelled.load()
        #expect(cancelled.recovery == .loading)
    }
}

/// Hands out queued health histories.
private actor HealthResults {
    var queue: [Result<HealthHistory, Problem>]

    init(_ queue: [Result<HealthHistory, Problem>]) {
        self.queue = queue
    }

    func next() throws -> HealthHistory {
        try queue.removeFirst().get()
    }
}
