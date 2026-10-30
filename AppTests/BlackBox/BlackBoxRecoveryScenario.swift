import Foundation
import GCPAPISync
import Testing

@testable import GCPAPISyncApp

/// A synthetic history for the recovery analysis: a hard day every `spacing` days from `lead`
/// on (a third of the training days, with rising loads), two easy days in between, and each
/// metric at a usual level, optionally with noise, a drift, outliers, missing days and a planted
/// response to the hard days.
nonisolated struct RecoveryScenario {
    static let start = GarminDate.day("2025-01-06")
    static let levels: [OverviewMetric: Double] = [
        .hrv: 50, .restingHeartRate: 50, .sleepScore: 80, .stress: 30,
    ]

    /// Each day's training load.
    var loads: [Double]
    /// Each metric's value per day.
    var values: [OverviewMetric: [Int?]]
    /// The days the hard days were planted on.
    let planted: [Int]

    /// `noise` is the largest deviation from the usual level by metric, `drift` its change per
    /// day, and `effect` the factor a metric is multiplied by `lag` days after a hard day.
    init(
        count: Int = 300, spacing: Int = 8, lead: Int = 40, seed: UInt64 = 1,
        noise: [OverviewMetric: Int] = [:], drift: [OverviewMetric: Double] = [:],
        outliers: Double = 0, missing: Double = 0,
        effect: (OverviewMetric, Int) -> Double = { _, _ in 1 }
    ) {
        var random = BlackBoxRandom(seed: seed)
        var loads = Array(repeating: 0.0, count: count)
        var planted: [Int] = []
        var lagOf: [Int: Int] = [:]
        for day in stride(from: lead, to: count - 3, by: spacing) {
            loads[day] = 300 + Double(planted.count)
            planted.append(day)
            for lag in 0...3 {
                lagOf[day + lag] = lag
            }
            for offset in [1, 5] where day + offset < count {
                loads[day + offset] = 20 + Double((day + offset) % 7)
            }
        }
        var values: [OverviewMetric: [Int?]] = [:]
        for metric in [OverviewMetric.hrv, .restingHeartRate, .sleepScore, .stress] {
            let level = Self.levels[metric] ?? 0
            values[metric] = (0..<count).map { day -> Int? in
                let spread = noise[metric] ?? 0
                var value = level + (drift[metric] ?? 0) * Double(day)
                value += Double(random.integer(-spread...spread))
                if let lag = lagOf[day] {
                    value *= effect(metric, lag)
                } else if random.uniform(0...1) < outliers {
                    value *= 3
                }
                return random.uniform(0...1) < missing ? nil : Int(value.rounded())
            }
        }
        self.loads = loads
        self.values = values
        self.planted = planted
    }

    var dates: [GarminDate] { AnalyticsBlackBox.dates(from: Self.start, count: loads.count) }

    var history: HealthHistory {
        HealthHistory(
            days: dates.enumerated().map { index, date in
                DayHealth(
                    date: date, restingHeartRate: values[.restingHeartRate]?[index],
                    hrv: values[.hrv]?[index],
                    sleep: values[.sleepScore]?[index].map { score in
                        SleepNight(
                            total: 28_800, deep: 5000, light: 15_000, rem: 6000, awake: 2800,
                            score: score)
                    },
                    stress: values[.stress]?[index])
            })
    }

    var loadDays: [TrainingLoad.Day] {
        zip(dates, loads).map { TrainingLoad.Day(date: $0, load: $1, fitness: 0, fatigue: 0) }
    }

    func response(
        hardShare: Double = 0.25, baselineDays: Int = RecoveryResponse.baselineDays
    ) -> RecoveryResponse {
        RecoveryResponse(
            history: history, loads: loadDays, hardShare: hardShare, baselineDays: baselineDays)
    }
}

/// The documented analysis, computed independently: each hard day is an event; a metric's
/// usual level is the median of the `baselineDays` days before it (from at least
/// `minimumBaseline` values), and its change `lag` days later is in percent of that level.
nonisolated struct RecoveryOracle {
    let byDate: [GarminDate: DayHealth]
    let events: [GarminDate]
    let baselineDays: Int

    init(history: HealthHistory, events: [GarminDate], baselineDays: Int) {
        byDate = Dictionary(history.days.map { ($0.date, $0) }) { first, _ in first }
        self.events = events
        self.baselineDays = baselineDays
    }

    /// The hard days of `loads` by `threshold`.
    static func hardDays(_ loads: [TrainingLoad.Day], threshold: Double?) -> [GarminDate] {
        guard let threshold else { return [] }
        return loads.filter { $0.load > 0 && $0.load >= threshold }.map(\.date)
    }

    static func value(_ metric: OverviewMetric, _ day: DayHealth?) -> Double? {
        guard let day else { return nil }
        switch metric {
        case .hrv: return day.hrv.map(Double.init)
        case .restingHeartRate: return day.restingHeartRate.map(Double.init)
        case .sleepScore: return day.sleep?.score.map(Double.init)
        case .stress: return day.stress.map(Double.init)
        case .vo2max: return day.vo2max
        }
    }

    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2)
            ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }

    /// The usual level of `metric` before `event`.
    func baseline(_ metric: OverviewMetric, before event: GarminDate) -> Double? {
        let window = (1...baselineDays).compactMap {
            Self.value(metric, byDate[event.adding(days: -$0)])
        }
        guard window.count >= RecoveryResponse.minimumBaseline else { return nil }
        return Self.median(window)
    }

    /// Every event's change of `metric` `lag` days after it, in percent.
    func changes(_ metric: OverviewMetric, lag: Int) -> [Double] {
        events.compactMap { event in
            guard let base = baseline(metric, before: event), base != 0,
                let value = Self.value(metric, byDate[event.adding(days: lag)])
            else { return nil }
            return 100 * (value - base) / base
        }
    }

    /// The two-sided 97.5 % quantile of Student's t distribution, rounded up.
    static func studentT(degrees: Int) -> Double {
        let table = [
            12.71, 4.303, 3.183, 2.777, 2.571, 2.447, 2.365, 2.306, 2.263, 2.229, 2.201, 2.179,
            2.161, 2.145, 2.132, 2.120, 2.110, 2.101, 2.094, 2.086, 2.080, 2.074, 2.069, 2.064,
            2.060, 2.056, 2.052, 2.049, 2.046, 2.043,
        ]
        guard degrees >= 1 else { return .infinity }
        return degrees <= table.count ? table[degrees - 1] : table[table.count - 1]
    }

    /// The narrowest and widest 95 % half-width a reasonable estimate of the mean of `changes`
    /// can have: a normal one from the population deviation, or Student's from the sample's.
    static func marginBounds(_ changes: [Double]) -> ClosedRange<Double> {
        let count = Double(changes.count)
        let mean = changes.reduce(0, +) / count
        let squares = changes.map { ($0 - mean) * ($0 - mean) }.reduce(0, +)
        let population = (squares / count).squareRoot()
        let sample = (squares / (count - 1)).squareRoot()
        let low = 1.959 * population / count.squareRoot()
        let high = studentT(degrees: changes.count - 1) * sample / count.squareRoot()
        return (low * 0.999 - 1e-9)...(high * 1.001 + 1e-9)
    }
}

/// Checks a response's hard-day curves against the oracle.
@MainActor
enum RecoveryCheck {
    static func expectMatchesOracle(
        _ response: RecoveryResponse, scenario: RecoveryScenario, baselineDays: Int,
        metrics: [OverviewMetric] = RecoveryResponse.metrics
    ) {
        let hard = RecoveryOracle.hardDays(scenario.loadDays, threshold: response.threshold)
        #expect(response.hardDays == hard.count)
        let oracle = RecoveryOracle(
            history: scenario.history, events: hard, baselineDays: baselineDays)
        for metric in metrics {
            guard let curve = response.curves.first(where: { $0.metric == metric }) else {
                Issue.record("No curve for \(metric)")
                continue
            }
            for lag in RecoveryResponse.lags {
                let changes = oracle.changes(metric, lag: lag)
                let point = curve.hard.first { $0.lag == lag }
                guard let point else {
                    #expect(changes.isEmpty, "\(metric) has no point at lag \(lag)")
                    continue
                }
                #expect(point.events == changes.count, "\(metric) events at lag \(lag)")
                guard !changes.isEmpty else { continue }
                let mean = changes.reduce(0, +) / Double(changes.count)
                #expect(
                    AnalyticsBlackBox.isClose(point.mean, mean, tolerance: 1e-9),
                    "\(metric) mean at lag \(lag): \(point.mean) instead of \(mean)")
                if changes.count >= 3 {
                    let bounds = RecoveryOracle.marginBounds(changes)
                    #expect(
                        bounds.contains(point.margin),
                        "\(metric) margin at lag \(lag): \(point.margin) not in \(bounds)")
                }
            }
        }
    }
}
