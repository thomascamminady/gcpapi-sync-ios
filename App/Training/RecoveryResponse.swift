import Foundation
import GCPAPISync

/// How HRV, resting heart rate, sleep and stress respond to hard training, learned from the
/// user's own history.
///
/// A superposed epoch analysis (an event-related average): each hard training day is an
/// event, and every metric on the days around it is compared with its usual level, the median
/// of the 28 days before the event. Averaging over many events cancels out what happens by
/// chance and leaves the typical response. Rest days, averaged the same way, are the control.
nonisolated struct RecoveryResponse: Hashable, Codable, Sendable {
    /// Days relative to the training day: the day before, the day itself and three after.
    static let lags = Array(-1...3)
    /// Days before an event whose median is the usual level.
    static let baselineDays = 28
    /// The fewest values a usual level is computed from.
    static let minimumBaseline = 10
    /// The share of training days, by load, that count as hard.
    static let hardShare = 0.2
    /// The fewest events a conclusion is drawn from.
    static let minimumEvents = 6
    static let metrics: [OverviewMetric] = [.hrv, .restingHeartRate, .sleepScore, .stress]

    /// The mean change from the usual level `lag` days after the events, in percent, and the
    /// half-width of its 95% confidence interval.
    struct Point: Hashable, Codable, Sendable {
        let lag: Int
        let mean: Double
        let margin: Double
        /// The events with a value on this day.
        let events: Int

        /// Whether enough events moved the metric for the change to be told from chance.
        var isClear: Bool {
            events >= RecoveryResponse.minimumEvents && abs(mean) > margin
        }
    }

    /// A metric's response to hard days and to rest days.
    struct Curve: Hashable, Codable, Sendable, Identifiable {
        let metric: OverviewMetric
        let hard: [Point]
        let rest: [Point]

        var id: OverviewMetric { metric }

        /// The largest change on the training day or after it.
        var peak: Point? {
            hard.filter { $0.lag >= 0 && $0.events >= RecoveryResponse.minimumEvents }
                .max { abs($0.mean) < abs($1.mean) }
        }

        /// Days after training until the change can no longer be told from chance.
        var recoveredAfter: Int? {
            guard let peak, peak.isClear else { return nil }
            return hard.first { $0.lag > peak.lag && $0.events > 0 && !$0.isClear }?.lag
        }

        /// What the curve says, in a sentence.
        var sentence: String {
            guard let peak else {
                return String(localized: "Not enough \(metric.title) data around hard days yet.")
            }
            guard peak.isClear else {
                return String(localized: "No clear change in \(metric.title) after hard training.")
            }
            let size = (abs(peak.mean) / 100).formatted(.percent.precision(.fractionLength(0)))
            let change =
                peak.mean > 0
                ? String(localized: "\(size) higher") : String(localized: "\(size) lower")
            let when = Self.phrase(lag: peak.lag)
            let title = metric.title
            guard let days = recoveredAfter else {
                return String(
                    localized:
                        "\(title) is \(change) \(when) and not back to usual after three days.")
            }
            return String(
                localized:
                    "\(title) is \(change) \(when) and back to usual within \(Format.days(days)).")
        }

        private static func phrase(lag: Int) -> String {
            switch lag {
            case 0: String(localized: "on hard training days")
            case 1: String(localized: "the day after hard training")
            default: String(localized: "\(lag) days after hard training")
            }
        }
    }

    let curves: [Curve]
    /// The share of training days that counted as hard, and the days of the usual level.
    let hardShare: Double
    let baselineDays: Int
    let hardDays: Int
    let restDays: Int
    /// The training load from which a day counts as hard.
    let threshold: Double?

    /// Whether there are enough hard days to say anything.
    var isSufficient: Bool { hardDays >= Self.minimumEvents }

    /// The curve with the clearest response, HRV when it has one.
    var headline: Curve? {
        let clear = curves.filter { $0.peak?.isClear == true }
        return clear.first { $0.metric == .hrv }
            ?? clear.max { strength($0) < strength($1) } ?? curves.first
    }

    private func strength(_ curve: Curve) -> Double {
        guard let peak = curve.peak, peak.margin > 0 else { return 0 }
        return abs(peak.mean) / peak.margin
    }

    init(
        history: HealthHistory, loads: [TrainingLoad.Day], hardShare: Double = hardShare,
        baselineDays: Int = baselineDays
    ) {
        self.hardShare = hardShare
        self.baselineDays = baselineDays
        let loadByDate = Dictionary(loads.map { ($0.date, $0.load) }) { first, _ in first }
        let trainingLoads = loads.map(\.load).filter { $0 > 0 }.sorted()
        let threshold =
            trainingLoads.isEmpty
            ? nil
            : trainingLoads[
                max(0, Int(((1 - hardShare) * Double(trainingLoads.count)).rounded(.up)) - 1)]
        func isHard(_ date: GarminDate) -> Bool {
            guard let threshold, let load = loadByDate[date] else { return false }
            return load >= threshold
        }
        // The first day of a block of hard days, and rest days after a day that was not hard.
        let hard = loads.map(\.date).filter { isHard($0) && !isHard($0.adding(days: -1)) }
        let rest = loads.filter { $0.load == 0 && !isHard($0.date.adding(days: -1)) }.map(\.date)
        let byDate = Dictionary(history.days.map { ($0.date, $0) }) { first, _ in first }
        curves = Self.metrics.map { metric in
            Curve(
                metric: metric,
                hard: Self.points(metric, around: hard, in: byDate, baselineDays: baselineDays),
                rest: Self.points(metric, around: rest, in: byDate, baselineDays: baselineDays))
        }
        hardDays = hard.count
        restDays = rest.count
        self.threshold = threshold
    }

    private static func points(
        _ metric: OverviewMetric, around events: [GarminDate], in days: [GarminDate: DayHealth],
        baselineDays: Int
    ) -> [Point] {
        let changes: [Int: [Double]] = events.reduce(into: [:]) { result, event in
            let before = (1...baselineDays).compactMap { offset in
                days[event.adding(days: -offset)].flatMap(metric.value)
            }
            guard before.count >= minimumBaseline, let usual = median(before), usual > 0 else {
                return
            }
            for lag in lags {
                if let value = days[event.adding(days: lag)].flatMap(metric.value) {
                    result[lag, default: []].append((value - usual) / usual * 100)
                }
            }
        }
        return lags.map { lag in
            let values = changes[lag] ?? []
            let count = Double(values.count)
            let mean = values.isEmpty ? 0 : values.reduce(0, +) / count
            let variance =
                values.count > 1
                ? values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / (count - 1) : 0
            return Point(
                lag: lag, mean: mean, margin: 1.96 * (variance / max(1, count)).squareRoot(),
                events: values.count)
        }
    }

    static func median(_ values: [Double]) -> Double? {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return nil }
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2)
            ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }
}
