import Foundation

/// The folder a user's devices share their state through, picked once on each device: in
/// iCloud Drive, for instance. One file in it holds the ``SharedState``; each sync merges the
/// device's state into it.
nonisolated struct SyncFolder {
    static let file = "GCPAPI Sync.json"

    private let defaults: UserDefaults
    private static let bookmarkKey = "syncFolderBookmark"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The chosen folder, if it can still be reached.
    var folder: URL? {
        guard let data = defaults.data(forKey: Self.bookmarkKey) else { return nil }
        var isStale = false
        return try? URL(resolvingBookmarkData: data, bookmarkDataIsStale: &isStale)
    }

    /// Remember `folder`, picked in the document picker.
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

    /// Merge `local` with the state in the chosen folder, write the result there, and return
    /// it; `local` itself without a folder.
    func sync(_ local: SharedState) throws -> SharedState {
        guard let folder else { return local }
        let accessing = folder.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                folder.stopAccessingSecurityScopedResource()
            }
        }
        return try Self.sync(local, in: folder)
    }

    /// Merge `local` with the state in `folder` and write the result there, coordinated with
    /// the file provider (iCloud Drive downloads the file first, other devices wait).
    static func sync(_ local: SharedState, in folder: URL) throws -> SharedState {
        let url = folder.appending(path: file)
        var coordination: NSError?
        var result = Result<SharedState, any Error>.success(local)
        NSFileCoordinator().coordinate(
            writingItemAt: url, options: .forMerging, error: &coordination
        ) { url in
            result = Result {
                let remote = (try? Data(contentsOf: url)).flatMap {
                    try? JSONDecoder().decode(SharedState.self, from: $0)
                }
                let merged = remote.map { local.merged(with: $0) } ?? local
                if merged != remote {
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    try encoder.encode(merged).write(to: url, options: .atomic)
                }
                return merged
            }
        }
        if let coordination {
            throw coordination
        }
        return try result.get()
    }
}
