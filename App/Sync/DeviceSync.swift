import Foundation
import Observation

/// Keeps the planned routes and the settings in step with the chosen folder: when the app
/// becomes active and whenever either changes. The demo never syncs.
@Observable
final class DeviceSync {
    private(set) var folderName: String?
    private(set) var lastSynced: Date?
    private(set) var problem: Problem?
    private(set) var isSyncing = false
    /// Whether something changed while a sync ran, so that another one follows.
    private var isPending = false

    private let routes: RouteLibrary
    private let preferences: Preferences
    private let isEnabled: Bool
    private let perform: @Sendable (SharedState) throws -> SharedState

    /// Syncing `routes` and `preferences` through `perform`, which merges the device's state
    /// with the folder's and returns the result.
    init(
        routes: RouteLibrary, preferences: Preferences, isEnabled: Bool = true,
        folderName: String? = SyncFolder().folder?.lastPathComponent,
        perform: @escaping @Sendable (SharedState) throws -> SharedState = {
            try SyncFolder().sync($0)
        }
    ) {
        self.routes = routes
        self.preferences = preferences
        self.isEnabled = isEnabled
        self.folderName = isEnabled ? folderName : nil
        self.perform = perform
    }

    /// Sync with `folder`, picked in the document picker, from now on.
    func choose(_ folder: URL) async {
        do {
            try SyncFolder().choose(folder)
            folderName = folder.lastPathComponent
            await sync()
        } catch {
            problem = Problem(error)
        }
    }

    /// Stop syncing; what was synced stays.
    func stop() {
        SyncFolder().forget()
        folderName = nil
        lastSynced = nil
        problem = nil
    }

    /// Merge this device's routes and settings with the folder's, and take what is newer.
    func sync() async {
        guard isEnabled, folderName != nil else { return }
        guard !isSyncing else {
            isPending = true
            return
        }
        isSyncing = true
        let local = SharedState(
            routes: routes.routes, deletedRoutes: routes.deleted,
            settings: preferences.settings, settingsModified: preferences.modified)
        let perform = perform
        do {
            let merged = try await Task.detached { try perform(local) }.value
            routes.adopt(merged.routes, deleted: merged.deletedRoutes)
            if let settings = merged.settings, let modified = merged.settingsModified,
                modified > preferences.modified
            {
                preferences.adopt(settings, modified: modified)
            }
            lastSynced = .now
            problem = nil
        } catch {
            problem = Problem(error)
        }
        isSyncing = false
        if isPending {
            isPending = false
            await sync()
        }
    }
}
