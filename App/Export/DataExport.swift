import Foundation
import GCPAPISync
import Observation

/// Prepares export files and keeps the folder and the calendar in step with Garmin.
@Observable
final class DataExport {
    /// What an export contains.
    enum Content: String, CaseIterable, Identifiable {
        case daily
        case activities
        case calendar
        case json

        var id: Self { self }

        var title: String {
            switch self {
            case .daily: String(localized: "Daily Health (CSV)")
            case .activities: String(localized: "Activities (CSV)")
            case .calendar: String(localized: "Activities as Calendar (ICS)")
            case .json: String(localized: "Everything (JSON)")
            }
        }
    }

    enum Phase: Equatable {
        case idle
        case preparing
        case ready([URL])
        case failed(Problem)
    }

    private(set) var phase = Phase.idle
    /// The last time the folder or the calendar was brought up to date, and any problem.
    private(set) var lastSync: Date?
    private(set) var syncProblem: Problem?

    private let fetchHealth:
        @Sendable (_ end: GarminDate, _ days: Int) async throws -> HealthHistory
    private let fetchActivities:
        @Sendable (_ first: GarminDate, _ last: GarminDate) async throws -> [Workout]
    private let directory: URL

    init(
        directory: URL = .temporaryDirectory.appending(path: "Export"),
        fetchHealth:
            @escaping @Sendable (_ end: GarminDate, _ days: Int) async throws
            -> HealthHistory,
        fetchActivities:
            @escaping @Sendable (_ first: GarminDate, _ last: GarminDate) async throws
            -> [Workout]
    ) {
        self.directory = directory
        self.fetchHealth = fetchHealth
        self.fetchActivities = fetchActivities
    }

    /// An export of `client`'s data.
    convenience init(client: GarminClient) {
        self.init(
            fetchHealth: { end, days in
                try await HealthLoader.load(
                    from: client, endingOn: end, days: days, estimatingVO2max: false)
            },
            fetchActivities: { first, last in
                try await TrainingLoader.activities(from: client, first: first, last: last)
                    .compactMap(Workout.init)
            })
    }

    /// Fetch the last `days` days and write `contents` as files, ready to share.
    func prepare(days: Int, contents: Set<Content>, today: GarminDate = .today()) async {
        phase = .preparing
        do {
            let first = today.adding(days: 1 - days)
            async let history =
                contents.contains(.daily) || contents.contains(.json)
                ? fetchHealth(today, days) : HealthHistory(days: [])
            let needsActivities = contents.contains { $0 != .daily }
            async let workouts = needsActivities ? fetchActivities(first, today) : []
            let files = try write(
                days: try await history.days, workouts: try await workouts, contents: contents,
                suffix: "\(first)-\(today)")
            phase = .ready(files)
        } catch {
            guard !Task.isCancelled, !(error is CancellationError) else {
                phase = .idle
                return
            }
            phase = .failed(Problem(error))
        }
    }

    /// The activities of the last `days` days, for the calendar.
    func activities(days: Int, today: GarminDate = .today()) async throws -> [Workout] {
        try await fetchActivities(today.adding(days: 1 - days), today)
    }

    func reset() {
        phase = .idle
    }

    /// Bring the chosen folder and, when turned on, the calendar up to date.
    func sync(
        days: [DayHealth], workouts: [Workout], folder: FolderSync, calendar: CalendarSync?
    ) {
        do {
            try folder.export(days: days, workouts: workouts)
            if let calendar, let first = workouts.compactMap(\.start).min() {
                try calendar.sync(workouts, from: first)
            }
            lastSync = .now
            syncProblem = nil
        } catch {
            syncProblem = Problem(error)
        }
    }

    private func write(
        days: [DayHealth], workouts: [Workout], contents: Set<Content>, suffix: String
    ) throws -> [URL] {
        try? FileManager.default.removeItem(at: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var files: [URL] = []
        func save(_ data: Data, _ name: String) throws {
            let url = directory.appending(path: name)
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            files.append(url)
        }
        for content in Content.allCases where contents.contains(content) {
            switch content {
            case .daily:
                try save(Data(Exporter.dailyCSV(days).utf8), "garmin-daily-\(suffix).csv")
            case .activities:
                try save(
                    Data(Exporter.activitiesCSV(workouts).utf8), "garmin-activities-\(suffix).csv")
            case .calendar:
                try save(Data(Exporter.calendar(workouts).utf8), "garmin-activities-\(suffix).ics")
            case .json:
                try save(try Exporter.json(days: days, workouts: workouts), "garmin-\(suffix).json")
            }
        }
        return files
    }
}
