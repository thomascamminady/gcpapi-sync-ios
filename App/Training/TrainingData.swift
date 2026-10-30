import Foundation
import GCPAPISync

/// One week of training.
nonisolated struct TrainingWeek: Identifiable, Hashable, Codable, Sendable {
    /// The week's first day, by the user's calendar.
    let start: GarminDate
    /// Seconds per sport.
    let seconds: [Sport: Double]
    let activityCount: Int
    let load: Double

    var id: GarminDate { start }
    var total: Double { seconds.values.reduce(0, +) }

    /// The `count` weeks up to the one containing `last`, oldest first.
    static func weeks(
        _ workouts: [Workout], through last: GarminDate, count: Int, calendar: Calendar
    ) -> [Self] {
        let current = weekStart(of: last, calendar: calendar)
        let byWeek = Dictionary(grouping: workouts) { weekStart(of: $0.date, calendar: calendar) }
        return (0..<count).map { index in
            let start = current.adding(days: 7 * (index + 1 - count))
            let workouts = byWeek[start] ?? []
            return Self(
                start: start,
                seconds: workouts.reduce(into: [:]) { $0[$1.sport, default: 0] += $1.duration },
                activityCount: workouts.count,
                load: workouts.reduce(0) { $0 + ($1.trainingLoad ?? 0) })
        }
    }

    /// The first day of the week containing `date`, by `calendar`'s first weekday.
    static func weekStart(of date: GarminDate, calendar: Calendar) -> GarminDate {
        date.adding(days: -((date.weekday - calendar.firstWeekday + 7) % 7))
    }
}

extension GarminDate {
    /// The day of the week, 1 (Sunday) to 7 (Saturday) as `Calendar` counts them, from the
    /// date alone: no time zone can move it, not even one whose clocks skip midnight.
    nonisolated var weekday: Int {
        // 1 January 2000 was a Saturday.
        let days = ((try? GarminDate(year: 2000, month: 1, day: 1)) ?? self).days(to: self)
        return ((days + 6) % 7 + 7) % 7 + 1
    }
}

/// Garmin's heart rate zones for one sport: the lowest heart rate of zones 1 to 5.
nonisolated struct HeartRateZoneSet: Hashable, Codable, Sendable {
    let floors: [Int]
    let maximum: Int?

    init?(_ zones: HeartRateZones) {
        let floors = [
            zones.zone1Floor, zones.zone2Floor, zones.zone3Floor, zones.zone4Floor,
            zones.zone5Floor,
        ].compactMap(\.self)
        guard floors.count == 5 else { return nil }
        self.floors = floors
        maximum = zones.maxHeartRateUsed
    }

    /// `142–156 bpm` for zone `index` (0 to 4).
    func label(zone index: Int) -> String {
        let low = floors[index]
        if index + 1 < floors.count {
            return "\(low)–\(floors[index + 1] - 1) bpm"
        }
        return maximum.map { "\(low)–\($0) bpm" } ?? "\(low)+ bpm"
    }
}

/// What the training screens show.
nonisolated struct TrainingData: Hashable, Codable, Sendable {
    /// The activities shown, newest first.
    let workouts: [Workout]
    /// Every activity loaded, including those before the days shown, newest first.
    let history: [Workout]
    /// One day each, oldest first, including the days before those shown.
    let loadHistory: [TrainingLoad.Day]
    /// Oldest first.
    let weeks: [TrainingWeek]
    /// Heart rate zones by Garmin sport name, such as `RUNNING` or `DEFAULT`.
    let zones: [String: HeartRateZoneSet]

    /// The days shown, oldest first.
    var load: [TrainingLoad.Day] {
        Array(loadHistory.suffix(TrainingLoader.shownDays))
    }

    /// The zones Garmin uses for `sport`.
    func heartRateZones(for sport: Sport) -> HeartRateZoneSet? {
        let name =
            switch sport {
            case .running: "RUNNING"
            case .cycling: "CYCLING"
            case .swimming: "SWIMMING"
            default: "DEFAULT"
            }
        return zones[name] ?? zones["DEFAULT"]
    }
}

/// Fetches activities and turns them into ``TrainingData``.
nonisolated enum TrainingLoader {
    /// Days shown in the charts and the activity list.
    static let shownDays = 90
    /// Days before those, so that fitness has built up by the first day shown.
    static let warmUpDays = 120
    /// Weeks in the volume chart.
    static let shownWeeks = 12
    /// The activity search pages by at most 45, so the range is split into windows that are
    /// fetched a few at a time.
    static let windowDays = 14
    static let concurrentWindows = 4

    static func load(
        from client: GarminClient, endingOn end: GarminDate,
        analysis: AnalysisSettings = AnalysisSettings()
    ) async throws -> TrainingData {
        let first = end.adding(days: 1 - shownDays - warmUpDays)
        async let zones = client.getHeartRateZones()
        let activities = try await activities(from: client, first: first, last: end)
        return assemble(
            activities: activities, zones: try await zones, endingOn: end, calendar: .app,
            analysis: analysis)
    }

    /// Every activity from `first` through `last`.
    static func activities(
        from client: GarminClient, first: GarminDate, last: GarminDate
    )
        async throws -> [SummarizedActivity]
    {
        let windows = stride(from: 0, through: first.days(to: last), by: windowDays).map { offset in
            (first.adding(days: offset), min(first.adding(days: offset + windowDays - 1), last))
        }
        return try await withThrowingTaskGroup(of: [SummarizedActivity].self) { group in
            var pending = windows.makeIterator()
            func next() -> Bool {
                guard let (start, end) = pending.next() else { return false }
                group.addTask {
                    try await client.searchActivities(
                        limit: 10_000, filters: ActivityFilters(startDate: start, endDate: end))
                }
                return true
            }
            for _ in 0..<concurrentWindows where !next() {
                break
            }
            var activities: [SummarizedActivity] = []
            while let page = try await group.next() {
                activities += page
                _ = next()
            }
            return activities
        }
    }

    static func assemble(
        activities: [SummarizedActivity], zones: [HeartRateZones], endingOn end: GarminDate,
        calendar: Calendar, analysis: AnalysisSettings = AnalysisSettings()
    ) -> TrainingData {
        // Windows do not overlap, but a changed activity could appear twice while paging.
        let unique = Dictionary(activities.map { ($0.activityId, $0) }) { first, _ in first }
        let workouts = unique.values.compactMap(Workout.init).sorted {
            ($0.start ?? .distantPast, $0.id) > ($1.start ?? .distantPast, $1.id)
        }
        let first = end.adding(days: 1 - shownDays - warmUpDays)
        let shownFrom = end.adding(days: 1 - shownDays)
        return TrainingData(
            workouts: workouts.filter { $0.date >= shownFrom && $0.date <= end },
            history: workouts.filter { $0.date <= end },
            loadHistory: TrainingLoad.days(
                workouts, from: first, through: end, fitnessDays: analysis.fitnessDays,
                fatigueDays: analysis.fatigueDays),
            weeks: TrainingWeek.weeks(
                workouts, through: end, count: shownWeeks, calendar: calendar),
            zones: zones.reduce(into: [:]) { result, zones in
                if let sport = zones.sport, let set = HeartRateZoneSet(zones) {
                    result[sport] = set
                }
            })
    }
}
