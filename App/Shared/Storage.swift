import Foundation

/// What the app last loaded, saved so that it opens with data at once.
///
/// Files are protected until the first unlock after a restart, so background refresh can
/// update them while the phone is locked, and they are excluded from backups: everything in
/// them can be fetched from Garmin again.
nonisolated struct SnapshotStore: Sendable {
    /// A saved value and when it was loaded.
    struct Snapshot<Value: Codable & Sendable>: Codable, Sendable {
        let saved: Date
        let value: Value
    }

    let directory: URL

    /// The app's own store, in Application Support.
    static let standard = Self(
        directory: URL.applicationSupportDirectory.appending(
            path: "Snapshots", directoryHint: .isDirectory))

    func save<Value: Codable & Sendable>(
        _ value: Value, as name: String, at date: Date = .now
    ) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var folder = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try folder.setResourceValues(values)
        let data = try JSONEncoder().encode(Snapshot(saved: date, value: value))
        try data.write(
            to: url(name), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func load<Value: Codable & Sendable>(_: Value.Type, named name: String) -> Snapshot<Value>? {
        guard let data = try? Data(contentsOf: url(name)) else { return nil }
        return try? JSONDecoder().decode(Snapshot<Value>.self, from: data)
    }

    /// Delete everything, as when signing out.
    func removeAll() {
        try? FileManager.default.removeItem(at: directory)
    }

    private func url(_ name: String) -> URL {
        directory.appending(path: "\(name).json")
    }
}

/// Activities' original recordings, kept so that opening an activity again needs no
/// download. They live in the caches directory, which the system may empty when space runs
/// low.
nonisolated struct RecordingCache: Sendable {
    let directory: URL

    static let standard = Self(
        directory: URL.cachesDirectory.appending(path: "Recordings", directoryHint: .isDirectory))

    func data(for id: Int) -> Data? {
        try? Data(contentsOf: url(id))
    }

    func store(_ data: Data, for id: Int) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(
            to: url(id), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func removeAll() {
        try? FileManager.default.removeItem(at: directory)
    }

    private func url(_ id: Int) -> URL {
        directory.appending(path: "\(id).fit")
    }
}
