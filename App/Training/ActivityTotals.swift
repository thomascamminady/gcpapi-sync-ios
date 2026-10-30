import Foundation
import GCPAPISync

/// The sums of a set of activities: a totals row of the activity log, or a month of the
/// statistics.
nonisolated struct ActivityTotals: Hashable, Sendable {
    /// Totals of one calendar month.
    struct Month: Identifiable, Hashable, Sendable {
        /// The month's first day.
        let first: GarminDate
        let totals: ActivityTotals

        var id: GarminDate { first }
    }

    let activityCount: Int
    /// Seconds.
    let duration: Double
    /// Metres.
    let distance: Double
    /// Seconds of the activities that have a distance, which their average speed is over.
    let durationWithDistance: Double
    /// Metres climbed.
    let ascent: Double
    /// Kilocalories.
    let calories: Double
    /// Garmin's training load.
    let load: Double
    /// The mean heart rate, weighted by duration, of the activities that have one.
    let averageHeartRate: Double?

    init(_ workouts: [Workout]) {
        activityCount = workouts.count
        duration = workouts.reduce(0) { $0 + $1.duration }
        let withDistance = workouts.filter { ($0.distance ?? 0) > 0 }
        distance = withDistance.reduce(0) { $0 + ($1.distance ?? 0) }
        durationWithDistance = withDistance.reduce(0) { $0 + $1.duration }
        ascent = workouts.reduce(0) { $0 + ($1.elevationGain ?? 0) }
        calories = workouts.reduce(0) { $0 + ($1.calories ?? 0) }
        load = workouts.reduce(0) { $0 + ($1.trainingLoad ?? 0) }
        let withHeartRate = workouts.filter { $0.averageHeartRate != nil && $0.duration > 0 }
        let heartRateDuration = withHeartRate.reduce(0) { $0 + $1.duration }
        averageHeartRate =
            heartRateDuration > 0
            ? withHeartRate.reduce(0) { $0 + ($1.averageHeartRate ?? 0) * $1.duration }
                / heartRateDuration
            : nil
    }

    /// Metres per second over the activities with a distance.
    var averageSpeed: Double? {
        distance > 0 && durationWithDistance > 0 ? distance / durationWithDistance : nil
    }

    /// The totals of each sport in `workouts`, in the order of `Sport.allCases`.
    static func bySport(_ workouts: [Workout]) -> [(sport: Sport, totals: Self)] {
        let grouped = Dictionary(grouping: workouts, by: \.sport)
        return Sport.allCases.compactMap { sport in
            grouped[sport].map { (sport, Self($0)) }
        }
    }

    /// The totals of the `count` calendar months up to the one containing `last`, newest first;
    /// months without activities have zero totals.
    static func months(_ workouts: [Workout], count: Int, through last: GarminDate) -> [Month] {
        let newest = CalendarMonth.first(of: last)
        let grouped = Dictionary(grouping: workouts) { CalendarMonth.first(of: $0.date) }
        return (0..<max(count, 0)).map { offset in
            let first = CalendarMonth.adding(months: -offset, to: newest)
            return Month(first: first, totals: Self(grouped[first] ?? []))
        }
    }
}

/// How training is spread over the days of a week, as Carl Foster described it.
nonisolated enum LoadBalance {
    /// The mean daily load divided by its standard deviation (of a sample): about 1 for varied
    /// days, more than 2 when every day is alike. `nil` for fewer than two days or none that
    /// differ.
    static func monotony(_ loads: [Double]) -> Double? {
        guard loads.count > 1 else { return nil }
        let mean = loads.reduce(0, +) / Double(loads.count)
        let variance =
            loads.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(loads.count - 1)
        guard variance > 0 else { return nil }
        return mean / variance.squareRoot()
    }

    /// The total load times its monotony: high when much training is also monotonous.
    static func strain(_ loads: [Double]) -> Double? {
        monotony(loads).map { $0 * loads.reduce(0, +) }
    }

    /// Fatigue over fitness, the acute to chronic workload ratio: about 1 when training as
    /// usual, above 1.5 when far more. `nil` without fitness.
    static func workloadRatio(_ day: TrainingLoad.Day) -> Double? {
        day.fitness > 0 ? day.fatigue / day.fitness : nil
    }
}
