import Foundation
import GCPAPISync
import Testing

@testable import GCPAPISyncApp

/// A point with plenty of events.
private func point(
    _ lag: Int, _ mean: Double, margin: Double = 1, events: Int = 100
)
    -> RecoveryResponse.Point
{
    RecoveryResponse.Point(lag: lag, mean: mean, margin: margin, events: events)
}

/// A curve of HRV whose hard days changed by `means` on lags -1 through 3.
private func curve(_ means: [Double], margin: Double = 1) -> RecoveryResponse.Curve {
    RecoveryResponse.Curve(
        metric: .hrv, hard: zip(RecoveryResponse.lags, means).map { point($0, $1, margin: margin) },
        rest: RecoveryResponse.lags.map { point($0, 0) })
}

@Suite("Recovery response: points, curves and medians")
struct BlackBoxRecoveryPartsTests {
    @Test(
        "A change is clear when its confidence interval leaves out zero",
        arguments: [
            (-20.0, 5.0, true), (3.0, 1.0, true), (-2.0, 4.0, false), (0.0, 0.0, false),
            (6.0, 6.5, false), (-0.5, 0.1, true),
        ])
    func clearness(mean: Double, margin: Double, clear: Bool) {
        #expect(point(1, mean, margin: margin).isClear == clear)
    }

    @Test("A change needs enough events to be clear")
    func enoughEvents() {
        let enough = RecoveryResponse.minimumEvents
        #expect(point(0, -20, events: enough).isClear)
        #expect(!point(0, -20, events: enough - 1).isClear)
        #expect(!point(0, -20, events: 0).isClear)
    }

    @Test("The peak is the largest change on the training day or after it")
    func peak() throws {
        #expect(try #require(curve([-50, -5, -12, 8, 1]).peak).lag == 1)
        #expect(try #require(curve([0, 3, -2, 10, 0]).peak).lag == 2)
        #expect(try #require(curve([90, -1, 0.5, 0.2, -30]).peak).lag == 3)
        #expect(try #require(curve([1, 2, 1, 0, 0]).peak).mean == 2)
    }

    @Test("Without points from the training day on there is no peak")
    func noPeak() {
        let before = RecoveryResponse.Curve(metric: .hrv, hard: [point(-1, -40)], rest: [])
        #expect(before.peak == nil)
        #expect(RecoveryResponse.Curve(metric: .stress, hard: [], rest: []).peak == nil)
    }

    @Test(
        "Recovery: the days until the change can no longer be told from chance",
        arguments: [
            ([0.0, -20, -15, 0.5, 0.2], 2), ([0.0, -0.5, 12, 0.3, 0], 2),
            ([0.0, -9, 0.3, 0.2, 0.1], 1), ([0.0, -20, -12, -6, 0.4], 3),
        ] as [([Double], Int)])
    func recoveredAfter(means: [Double], days: Int) {
        #expect(curve(means).recoveredAfter == days)
    }

    @Test("Every curve says something, and a clear response is told apart from none")
    func sentences() {
        let clear = curve([0, -20, -15, 0.5, 0.2])
        let none = curve([0.1, 0.2, -0.3, 0.1, 0])
        #expect(!clear.sentence.isEmpty)
        #expect(!none.sentence.isEmpty)
        #expect(clear.sentence != none.sentence)
        #expect(clear.id == .hrv)
    }

    @Test(
        "Medians",
        arguments: [
            ([5.0], 5.0), ([1, 3], 2), ([3, 1, 2], 2), ([4, 1, 3, 2], 2.5),
            ([-5, 10, -1, 7, 0], 0), ([2, 2, 2, 9], 2), ([1e6, -1e6], 0),
        ] as [([Double], Double)])
    func medians(values: [Double], median: Double) {
        #expect(RecoveryResponse.median(values) == median)
    }

    @Test("No values, no median")
    func emptyMedian() {
        #expect(RecoveryResponse.median([]) == nil)
    }

    @Test("The median does not depend on the order and agrees with a sorted lookup")
    func randomMedians() {
        var random = BlackBoxRandom(seed: 77)
        for size in 1...60 {
            var values = (0..<size).map { _ in random.uniform(-100...100) }
            let expected = RecoveryOracle.median(values)
            #expect(RecoveryResponse.median(values) == expected)
            values.shuffle(using: &random)
            #expect(RecoveryResponse.median(values) == expected)
        }
    }

    @Test("HRV, resting heart rate, sleep and stress are analyzed")
    func metrics() {
        let metrics = Set(RecoveryResponse.metrics)
        #expect(metrics.isSuperset(of: [.hrv, .restingHeartRate, .sleepScore, .stress]))
        #expect(RecoveryResponse.metrics.count == metrics.count)
    }
}

@Suite("Recovery response: hard days and thresholds")
struct BlackBoxRecoveryThresholdTests {
    private func loads(_ values: [Double]) -> [TrainingLoad.Day] {
        AnalyticsBlackBox.dates(from: RecoveryScenario.start, count: values.count).enumerated().map
        {
            TrainingLoad.Day(date: $1, load: values[$0], fitness: 0, fatigue: 0)
        }
    }

    private func history(days: Int) -> HealthHistory {
        HealthHistory(
            days: AnalyticsBlackBox.dates(from: RecoveryScenario.start, count: days).map {
                DayHealth(date: $0, restingHeartRate: 50, hrv: 50, stress: 30)
            })
    }

    @Test("Without training there are no hard days and nothing to say")
    func noTraining() {
        let response = RecoveryResponse(
            history: history(days: 100), loads: loads(Array(repeating: 0, count: 100)))
        #expect(response.threshold == nil)
        #expect(response.hardDays == 0)
        #expect(!response.isSufficient)
    }

    @Test("Without any data there is nothing to say")
    func empty() {
        let response = RecoveryResponse(history: HealthHistory(days: []), loads: [])
        #expect(response.threshold == nil)
        #expect(response.hardDays == 0)
        #expect(response.restDays == 0)
        #expect(!response.isSufficient)
        #expect(response.curves.allSatisfy { curve in curve.hard.allSatisfy { $0.events == 0 } })
    }

    @Test(
        "The hardest share of training days count as hard, rest days never",
        arguments: [0.1, 0.2, 0.25, 0.5])
    func separatedShare(hardShare: Double) throws {
        // 100 training days with loads 1 to 100 in random order, each after a rest day.
        var random = BlackBoxRandom(seed: 5)
        let training = (1...100).map(Double.init).shuffled(using: &random)
        let days = loads(Array(repeating: 0, count: 40) + training.flatMap { [0, $0] })
        let response = RecoveryResponse(
            history: history(days: days.count), loads: days, hardShare: hardShare)
        let threshold = try #require(response.threshold)
        #expect(response.hardShare == hardShare)
        #expect(threshold > 0)
        #expect(response.hardDays == days.filter { $0.load >= threshold }.count)
        #expect(abs(Double(response.hardDays) - hardShare * 100) <= 1)
        #expect(threshold >= 100 * (1 - hardShare) - 1)
        #expect(threshold <= 100 * (1 - hardShare) + 2)
        #expect(response.restDays > 0)
        #expect(response.restDays <= 140)
    }

    @Test("Enough hard days are sufficient, too few are not")
    func sufficiency() {
        for training in stride(from: 5, through: 80, by: 5) {
            var values = Array(repeating: 0.0, count: 40)
            for index in 0..<training {
                values += [Double(10 + index), 0, 0, 0]
            }
            let response = RecoveryResponse(
                history: history(days: values.count), loads: loads(values), hardShare: 0.2)
            #expect(
                response.isSufficient == (response.hardDays >= RecoveryResponse.minimumEvents),
                "\(training) training days, \(response.hardDays) hard")
        }
    }

    @Test("The parameters are reported back")
    func parameters() {
        let response = RecoveryScenario().response(hardShare: 0.3, baselineDays: 21)
        #expect(response.hardShare == 0.3)
        #expect(response.baselineDays == 21)
        let defaults = RecoveryResponse(
            history: RecoveryScenario().history, loads: RecoveryScenario().loadDays)
        #expect(defaults.hardShare == RecoveryResponse.hardShare)
        #expect(defaults.baselineDays == RecoveryResponse.baselineDays)
    }
}
