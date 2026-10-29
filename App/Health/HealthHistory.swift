import Foundation
import GCPAPISync

/// One night of sleep, in seconds per stage.
nonisolated struct SleepNight: Hashable, Sendable {
    var total: Int
    var deep: Int
    var light: Int
    var rem: Int
    var awake: Int
    var score: Int?
}

/// The health metrics of one calendar day; `nil` where Garmin has no data.
nonisolated struct DayHealth: Identifiable, Hashable, Sendable {
    let date: GarminDate
    var steps: Int?
    var stepGoal: Int?
    var restingHeartRate: Int?
    /// Overnight HRV average in milliseconds.
    var hrv: Int?
    /// Garmin's HRV status, such as `BALANCED`.
    var hrvStatus: String?
    /// The night ending on this day.
    var sleep: SleepNight?
    /// Average stress level (0-100).
    var stress: Int?
    var bodyBatteryLow: Int?
    var bodyBatteryHigh: Int?
    var activeCalories: Int?
    /// Moderate minutes plus twice the vigorous ones, as Garmin counts them.
    var intensityMinutes: Int?
    /// VO2max estimated from the runs of the 30 days ending on this day.
    var vo2max: Double?

    var id: GarminDate { date }

    /// Midnight at the start of this day, for charts.
    var start: Date { date.startOfDay(in: .current) }
}

/// A run of consecutive days, oldest first.
nonisolated struct HealthHistory: Hashable, Sendable {
    let days: [DayHealth]

    /// The mean of a metric over the days that have it.
    func average(_ metric: KeyPath<DayHealth, Int?>) -> Int? {
        let values = days.compactMap { $0[keyPath: metric] }
        guard !values.isEmpty else { return nil }
        return Int((Double(values.reduce(0, +)) / Double(values.count)).rounded())
    }

    /// The most recent day's value of a metric, if any day has it.
    func latest<Value>(_ metric: KeyPath<DayHealth, Value?>) -> Value? {
        days.reversed().lazy.compactMap { $0[keyPath: metric] }.first
    }

    /// The mean of a fractional metric over the days that have it.
    func mean(_ metric: KeyPath<DayHealth, Double?>) -> Double? {
        let values = days.compactMap { $0[keyPath: metric] }
        return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    /// The sum of a metric over the days that have it.
    func total(_ metric: KeyPath<DayHealth, Int?>) -> Int {
        days.compactMap { $0[keyPath: metric] }.reduce(0, +)
    }

    /// The mean sleep duration and score over the nights recorded.
    var averageSleep: SleepNight? {
        let nights = days.compactMap(\.sleep)
        guard !nights.isEmpty else { return nil }
        func mean(_ value: (SleepNight) -> Int) -> Int {
            Int((Double(nights.map(value).reduce(0, +)) / Double(nights.count)).rounded())
        }
        let scores = nights.compactMap(\.score)
        return SleepNight(
            total: mean(\.total), deep: mean(\.deep), light: mean(\.light), rem: mean(\.rem),
            awake: mean(\.awake),
            score: scores.isEmpty ? nil : scores.reduce(0, +) / scores.count
        )
    }
}

/// Fetches days of health data from Garmin.
nonisolated enum HealthLoader {
    /// The `days` days ending on `end`, fetched with five concurrent requests, or three
    /// without estimating VO2max.
    static func load(
        from client: GarminClient, endingOn end: GarminDate, days: Int = 7,
        estimatingVO2max: Bool = true
    ) async throws -> HealthHistory {
        let start = end.adding(days: 1 - days)
        async let summaries = client.getDailySummaries(start: start, end: end)
        async let sleep = client.getDailySleepSummaries(start: start, end: end)
        async let hrv = client.getDailyHRVSummaries(start: start, end: end)
        var runs: [SummarizedActivity] = []
        var zones: [HeartRateZones] = []
        if estimatingVO2max {
            // VO2max needs the runs of the 30 days before each day, and the maximum heart rate.
            async let searchedRuns = client.searchActivities(
                limit: 10_000,
                filters: ActivityFilters(
                    startDate: start.adding(days: 1 - VO2maxEstimator.window), endDate: end,
                    activityType: "running"))
            async let fetchedZones = client.getHeartRateZones()
            (runs, zones) = try await (searchedRuns, fetchedZones)
        }
        return assemble(
            dates: (0..<days).map { start.adding(days: $0) },
            summaries: try await summaries, sleep: try await sleep, hrv: try await hrv,
            runs: runs, zones: zones
        )
    }

    /// One `DayHealth` per date from Garmin's responses, which may miss days.
    static func assemble(
        dates: [GarminDate], summaries: [UserDailySummaryV2], sleep: [DailySleep],
        hrv: [HrvSummary], runs: [SummarizedActivity] = [], zones: [HeartRateZones] = []
    ) -> HealthHistory {
        let estimates =
            VO2maxEstimator.maxHeartRate(from: zones).map { maxHeartRate in
                runs.compactMap { VO2maxEstimator.estimate($0, maxHeartRate: maxHeartRate) }
            } ?? []
        let summaryByDay = Dictionary(
            summaries.compactMap { item in item.calendarDate.map { ($0, item) } }
        ) { first, _ in first }
        let sleepByDay = Dictionary(
            sleep.compactMap { item in item.calendarDate.map { ($0, item) } }
        ) { first, _ in first }
        let hrvByDay = Dictionary(
            hrv.compactMap { item in item.calendarDate.map { ($0, item) } }
        ) { first, _ in first }
        return HealthHistory(
            days: dates.map { date in
                var day = DayHealth(date: date)
                if let summary = summaryByDay[date] {
                    apply(summary, to: &day)
                }
                day.sleep = sleepByDay[date].flatMap(night)
                day.hrv = hrvByDay[date]?.lastNightAvg
                day.hrvStatus = hrvByDay[date]?.status
                day.vo2max = VO2maxEstimator.trend(estimates, on: date)
                return day
            })
    }

    private static func apply(_ summary: UserDailySummaryV2, to day: inout DayHealth) {
        day.steps = summary.movement?.steps?.value
        day.stepGoal = summary.movement?.steps?.goal
        day.restingHeartRate = summary.heartRate?.restingValue
        // Garmin reports negative stress levels when there was not enough data.
        day.stress = summary.stress?.avgLevel.flatMap { $0 >= 0 ? $0 : nil }
        day.bodyBatteryLow = summary.bodyBattery?.minValue
        day.bodyBatteryHigh = summary.bodyBattery?.maxValue
        day.activeCalories = summary.calories?.burnedActive
        if let minutes = summary.intensityMinutes,
            minutes.moderate != nil || minutes.vigorous != nil
        {
            day.intensityMinutes = (minutes.moderate ?? 0) + 2 * (minutes.vigorous ?? 0)
        }
    }

    private static func night(_ sleep: DailySleep) -> SleepNight? {
        guard let total = sleep.sleepTimeSeconds, total > 0 else { return nil }
        return SleepNight(
            total: total, deep: sleep.deepSleepSeconds ?? 0, light: sleep.lightSleepSeconds ?? 0,
            rem: sleep.remSleepSeconds ?? 0, awake: sleep.awakeSleepSeconds ?? 0,
            score: sleep.sleepScores?.overall?.value
        )
    }
}
