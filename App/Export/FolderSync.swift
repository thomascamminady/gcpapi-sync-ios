import Foundation

/// Keeps CSV files of the user's data up to date in a folder they chose in Files: on the
/// device, in iCloud Drive, Dropbox or any other file provider. Rows from earlier exports are
/// kept, so the files grow into a complete history.
nonisolated struct FolderSync {
    static let dailyFile = "garmin-daily.csv"
    static let activitiesFile = "garmin-activities.csv"

    private let defaults: UserDefaults
    private static let bookmarkKey = "exportFolderBookmark"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The chosen folder, if it can still be reached.
    var folder: URL? {
        guard let data = defaults.data(forKey: Self.bookmarkKey) else { return nil }
        var isStale = false
        return try? URL(resolvingBookmarkData: data, bookmarkDataIsStale: &isStale)
    }

    /// Remember `folder`, picked in the document picker, for later exports.
    func choose(_ folder: URL) throws {
        let accessing = folder.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                folder.stopAccessingSecurityScopedResource()
            }
        }
        defaults.set(try folder.bookmarkData(), forKey: Self.bookmarkKey)
    }

    func forget() {
        defaults.removeObject(forKey: Self.bookmarkKey)
    }

    /// Merge `days` and `workouts` into the files in the chosen folder.
    func export(days: [DayHealth], workouts: [Workout]) throws {
        guard let folder else { return }
        let accessing = folder.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                folder.stopAccessingSecurityScopedResource()
            }
        }
        try Self.write(days: days, workouts: workouts, to: folder)
    }

    /// Merge `days` and `workouts` into the CSV files in `folder`.
    static func write(days: [DayHealth], workouts: [Workout], to folder: URL) throws {
        let daily = folder.appending(path: dailyFile)
        let activities = folder.appending(path: activitiesFile)
        if !days.isEmpty {
            let merged = Exporter.merge(
                try? String(contentsOf: daily, encoding: .utf8), header: Exporter.dailyHeader,
                rows: days.map(Exporter.dailyRow), newestFirst: false)
            try merged.write(to: daily, atomically: true, encoding: .utf8)
        }
        if !workouts.isEmpty {
            let merged = Exporter.merge(
                try? String(contentsOf: activities, encoding: .utf8),
                header: Exporter.activityHeader, rows: workouts.map(Exporter.activityRow),
                newestFirst: true)
            try merged.write(to: activities, atomically: true, encoding: .utf8)
        }
    }
}
