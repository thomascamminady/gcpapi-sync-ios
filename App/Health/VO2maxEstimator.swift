import Foundation
import GCPAPISync

/// VO2max estimated from runs, because Garmin's Personal API does not return Garmin's own.
///
/// Like Runalyze's "effective VO2max": the oxygen cost of a run's grade-adjusted speed
/// (Daniels and Gilbert) divided by the share of VO2max its average heart rate implies
/// (Swain et al.: %HRmax = 0.64 %VO2max + 0.37). A day's value is the duration-weighted mean
/// of the estimates of the 30 days ending that day.
nonisolated enum VO2maxEstimator {
    /// Garmin's running activity types.
    static let runningTypes: Set<String> = [
        "running", "treadmill_running", "track_running", "street_running", "trail_running",
        "virtual_run", "indoor_running",
    ]
    /// Days of runs that contribute to a day's value.
    static let window = 30

    /// One run's estimate.
    struct Estimate: Hashable, Sendable {
        let date: GarminDate
        let duration: Double
        let vo2max: Double
    }

    /// The maximum heart rate Garmin uses: the running zones', else the default ones', else
    /// that of the first zones that have one; zones without one are skipped.
    static func maxHeartRate(from zones: [HeartRateZones]) -> Double? {
        let known = zones.filter { $0.maxHeartRateUsed != nil }
        let preferred =
            known.first { $0.sport == "RUNNING" } ?? known.first { $0.sport == "DEFAULT" }
            ?? known.first
        return preferred?.maxHeartRateUsed.map(Double.init)
    }

    /// Oxygen cost of running (ml/kg/min) at `speed` metres per minute.
    static func cost(metresPerMinute speed: Double) -> Double {
        -4.60 + 0.182258 * speed + 0.000104 * speed * speed
    }

    /// The estimate for a steady run of at least 15 minutes and 2.5 km at 50–100 % of
    /// VO2max, or `nil` for anything else.
    static func estimate(_ run: SummarizedActivity, maxHeartRate: Double) -> Estimate? {
        guard runningTypes.contains(run.activityType?.typeKey ?? ""),
            let date = run.startTimeLocal?.date,
            let duration = run.duration, duration >= 15 * 60,
            let distance = run.distance, distance >= 2500,
            let heartRate = run.averageHR,
            let speed = run.avgGradeAdjustedSpeed ?? run.averageSpeed, maxHeartRate > 0
        else { return nil }
        let fraction = (heartRate / maxHeartRate - 0.37) / 0.64
        let oxygen = cost(metresPerMinute: speed * 60)
        guard (0.5...1).contains(fraction), oxygen > 0 else { return nil }
        return Estimate(date: date, duration: duration, vo2max: oxygen / fraction)
    }

    /// The duration-weighted mean of the estimates of the `window` days ending on `day`.
    static func trend(_ estimates: [Estimate], on day: GarminDate) -> Double? {
        let first = day.adding(days: 1 - window)
        // In a fixed order, so that the sum does not depend on the order runs arrive in.
        let recent = estimates.filter { first <= $0.date && $0.date <= day }
            .sorted { ($0.date, $0.duration, $0.vo2max) < ($1.date, $1.duration, $1.vo2max) }
        let duration = recent.reduce(0) { $0 + $1.duration }
        guard duration > 0 else { return nil }
        return recent.reduce(0) { $0 + $1.vo2max * $1.duration } / duration
    }
}
