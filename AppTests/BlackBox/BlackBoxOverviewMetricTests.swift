import Foundation
import GCPAPISync
import Testing

@testable import GCPAPISyncApp

/// Days from the reference date with these HRV values.
private func hrvDays(_ values: [Int?]) -> [DayHealth] {
    zip(AnalyticsBlackBox.dates(from: AnalyticsBlackBox.reference, count: values.count), values).map
    {
        DayHealth(date: $0, hrv: $1)
    }
}

/// Days from the reference date with these resting heart rates.
private func heartRateDays(_ values: [Int?]) -> [DayHealth] {
    zip(AnalyticsBlackBox.dates(from: AnalyticsBlackBox.reference, count: values.count), values).map
    {
        DayHealth(date: $0, restingHeartRate: $1)
    }
}

private func expectClose(_ values: [Double], _ expected: [Double]) {
    #expect(values.count == expected.count)
    for (value, other) in zip(values, expected) {
        #expect(
            AnalyticsBlackBox.isClose(value, other, tolerance: 1e-12), "\(values) vs \(expected)")
    }
}

@Suite("Overview metrics")
struct BlackBoxOverviewMetricTests {
    private let day = DayHealth(
        date: AnalyticsBlackBox.reference, restingHeartRate: 48, hrv: 61,
        sleep: AnalyticsBlackBox.night(hours: 7.5, score: 82), stress: 27, vo2max: 51.5)

    @Test("Each metric's value of a day")
    func values() {
        #expect(OverviewMetric.hrv.value(of: day) == 61)
        #expect(OverviewMetric.restingHeartRate.value(of: day) == 48)
        #expect(OverviewMetric.sleepScore.value(of: day) == 82)
        #expect(OverviewMetric.stress.value(of: day) == 27)
        #expect(OverviewMetric.vo2max.value(of: day) == 51.5)
        let empty = DayHealth(date: AnalyticsBlackBox.reference)
        #expect(OverviewMetric.allCases.allSatisfy { $0.value(of: empty) == nil })
    }

    @Test("Resting heart rate and stress are better when lower")
    func lowerIsBetter() {
        #expect(OverviewMetric.restingHeartRate.lowerIsBetter)
        #expect(OverviewMetric.stress.lowerIsBetter)
        #expect(!OverviewMetric.hrv.lowerIsBetter)
        #expect(!OverviewMetric.sleepScore.lowerIsBetter)
        #expect(!OverviewMetric.vo2max.lowerIsBetter)
    }

    @Test("Each line shows a dashboard metric")
    func metrics() {
        #expect(OverviewMetric.hrv.metric == .hrv)
        #expect(OverviewMetric.restingHeartRate.metric == .restingHeartRate)
        #expect(OverviewMetric.sleepScore.metric == .sleep)
        #expect(OverviewMetric.stress.metric == .stress)
        #expect(OverviewMetric.vo2max.metric == .vo2max)
    }

    @Test("Titles and symbols tell the lines apart")
    func presentation() {
        let metrics = OverviewMetric.allCases
        #expect(metrics.allSatisfy { !$0.title.isEmpty && !$0.symbol.isEmpty && $0.id == $0 })
        #expect(Set(metrics.map(\.title)).count == metrics.count)
        #expect(Set(metrics.map(\.symbol)).count == metrics.count)
    }

    @Test(
        "A value with its unit",
        arguments: [
            (OverviewMetric.hrv, 61.0, "61"), (.restingHeartRate, 48, "48"),
            (.sleepScore, 82, "82"), (.stress, 27, "27"), (.vo2max, 52, "52"),
        ])
    func formatted(metric: OverviewMetric, value: Double, digits: String) {
        let text = metric.formatted(value)
        #expect(text.contains(digits))
        #expect(text != metric.formatted(nil))
        #expect(!metric.formatted(nil).isEmpty)
    }
}

@Suite("Overview metrics: scaling to 0...1")
struct BlackBoxOverviewScalingTests {
    @Test("The lowest value is 0, the highest 1, the rest in proportion")
    func proportional() {
        let days = hrvDays([40, 50, 60, nil, 45])
        let scaled = OverviewMetric.hrv.scaled(days)
        #expect(scaled.map(\.date) == [0, 1, 2, 4].map { days[$0].date })
        expectClose(scaled.map(\.value), [40, 50, 60, 45])
        expectClose(scaled.map(\.scaled), [0, 0.5, 1, 0.25])
    }

    @Test(
        "A metric that never changes sits at 0.5",
        arguments: [[55], [55, 55, 55], [nil, 70, nil, 70]])
    func constant(values: [Int?]) {
        let scaled = OverviewMetric.hrv.scaled(hrvDays(values))
        #expect(scaled.count == values.compactMap(\.self).count)
        #expect(scaled.allSatisfy { $0.scaled == 0.5 })
    }

    @Test("Without values there is nothing to scale")
    func empty() {
        #expect(OverviewMetric.hrv.scaled([]).isEmpty)
        #expect(OverviewMetric.hrv.scaled(hrvDays([nil, nil])).isEmpty)
        #expect(OverviewMetric.vo2max.scaled(hrvDays([40, 50])).isEmpty)
    }

    @Test("Better-when-lower metrics are flipped so that 1 is the best day")
    func higherIsBetter() {
        let days = heartRateDays([50, 60, 55])
        expectClose(OverviewMetric.restingHeartRate.scaled(days).map(\.scaled), [0, 1, 0.5])
        expectClose(
            OverviewMetric.restingHeartRate.scaled(days, higherIsBetter: true).map(\.scaled),
            [1, 0, 0.5])
        expectClose(
            OverviewMetric.restingHeartRate.scaled(days, higherIsBetter: true).map(\.value),
            [50, 60, 55])
        let hrv = hrvDays([50, 60, 55])
        #expect(
            OverviewMetric.hrv.scaled(hrv, higherIsBetter: true) == OverviewMetric.hrv.scaled(hrv))
    }

    @Test("Averaging: each value is the mean of the window ending on it")
    func averaging() {
        let days = hrvDays([10, 20, 30, 40, 50])
        let scaled = OverviewMetric.hrv.scaled(days, averaging: 3)
        #expect(scaled.map(\.date) == days[2...].map(\.date))
        expectClose(scaled.map(\.value), [20, 30, 40])
        expectClose(scaled.map(\.scaled), [0, 0.5, 1])
        #expect(OverviewMetric.hrv.scaled(days, averaging: 1) == OverviewMetric.hrv.scaled(days))
    }

    @Test("Too few days for one full window give nothing")
    func shortAveraging() {
        #expect(OverviewMetric.hrv.scaled(hrvDays([10, 20, 30]), averaging: 4).isEmpty)
        #expect(OverviewMetric.hrv.scaled(hrvDays([10, 20, 30]), averaging: 3).count == 1)
    }

    @Test("Random values: scaling ignores units and offsets", arguments: [UInt64(1), 2, 3, 4])
    func invariance(seed: UInt64) {
        var random = BlackBoxRandom(seed: seed)
        let values = (0..<60).map { _ -> Int? in
            random.uniform(0...1) < 0.2 ? nil : random.integer(20...120)
        }
        for averaging in [1, 3, 7] {
            for flip in [false, true] {
                let base = OverviewMetric.hrv.scaled(
                    hrvDays(values), averaging: averaging, higherIsBetter: flip)
                let moved = OverviewMetric.hrv.scaled(
                    hrvDays(values.map { $0.map { 3 * $0 + 17 } }), averaging: averaging,
                    higherIsBetter: flip)
                #expect(base.map(\.date) == moved.map(\.date))
                expectClose(moved.map(\.scaled), base.map(\.scaled))
                #expect(base.allSatisfy { (0...1).contains($0.scaled) })
                if Set(base.map(\.value)).count > 1 {
                    #expect(base.map(\.scaled).min() == 0)
                    #expect(base.map(\.scaled).max() == 1)
                }
            }
        }
    }
}
