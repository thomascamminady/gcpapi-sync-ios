import Foundation
import Testing

@testable import GCPAPISyncApp

@Suite struct SharedStateTests {
    private let start = GeoPoint(latitude: 47.36, longitude: 8.54)
    private let day = Date(timeIntervalSinceReferenceDate: 815_000_000)

    private func route(
        _ name: String, modified minutes: Double, id: UUID = UUID()
    )
        -> PlannedRoute
    {
        PlannedRoute(
            id: id, name: name, created: day, modified: day.addingTimeInterval(minutes * 60),
            waypoints: [start])
    }

    @Test func theNewerVersionOfARouteWins() {
        let id = UUID()
        let mine = SharedState(routes: [route("Old", modified: 1, id: id)])
        let theirs = SharedState(routes: [
            route("New", modified: 2, id: id), route("Other", modified: 0),
        ])
        let merged = mine.merged(with: theirs)
        #expect(Set(merged.routes.map(\.name)) == ["New", "Other"])
        #expect(theirs.merged(with: mine).routes.map(\.name).sorted() == ["New", "Other"])
    }

    @Test func deletionsWinOverOlderVersions() {
        let id = UUID()
        let mine = SharedState(routes: [route("Lake", modified: 1, id: id)])
        let theirs = SharedState(deletedRoutes: [id: day.addingTimeInterval(120)])
        let merged = mine.merged(with: theirs)
        #expect(merged.routes.isEmpty)
        #expect(merged.deletedRoutes[id] != nil)
    }

    @Test func aRouteChangedAfterItsDeletionIsBack() {
        let id = UUID()
        let mine = SharedState(routes: [route("Lake", modified: 5, id: id)])
        let theirs = SharedState(deletedRoutes: [id: day.addingTimeInterval(120)])
        let merged = mine.merged(with: theirs)
        #expect(merged.routes.map(\.id) == [id])
        #expect(merged.deletedRoutes[id] == nil)
    }

    @Test func theNewerSettingsWin() {
        var dense = Settings()
        dense.density = .dense
        let mine = SharedState(settings: Settings(), settingsModified: day)
        let theirs = SharedState(settings: dense, settingsModified: day.addingTimeInterval(1))
        #expect(mine.merged(with: theirs).settings == dense)
        #expect(theirs.merged(with: mine).settings == dense)
        #expect(mine.merged(with: SharedState()).settings == Settings())
    }

    @Test func twoDevicesMeetInTheFolder() throws {
        let folder = URL.temporaryDirectory.appending(path: "sync-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let phone = SharedState(routes: [route("From the phone", modified: 1)])
        let mac = SharedState(routes: [route("From the Mac", modified: 2)])
        let first = try SyncFolder.sync(phone, in: folder)
        #expect(first == phone)
        let second = try SyncFolder.sync(mac, in: folder)
        #expect(Set(second.routes.map(\.name)) == ["From the phone", "From the Mac"])
        // The phone gets the Mac's route the next time it syncs.
        let again = try SyncFolder.sync(phone, in: folder)
        #expect(again == second)
        #expect(
            FileManager.default.fileExists(atPath: folder.appending(path: SyncFolder.file).path))
    }
}

@Suite struct RouteSyncTests {
    private let start = GeoPoint(latitude: 47.36, longitude: 8.54)

    @Test func routesOfEarlierVersionsStillLoad() throws {
        let file = URL.temporaryDirectory.appending(path: "routes-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        // A file of an earlier version: an array of routes without modification dates.
        let created = Date(timeIntervalSinceReferenceDate: 815_000_000)
        let fields = [
            #""id":"\#(UUID().uuidString)""#, #""name":"Lake""#,
            #""created":\#(created.timeIntervalSinceReferenceDate)"#, #""waypoints":[]"#,
            #""legs":[]"#,
        ]
        let old = "[{\(fields.joined(separator: ","))}]"
        try Data(old.utf8).write(to: file)
        let saved = RouteStore(file: file).loadSaved()
        #expect(saved.routes.map(\.name) == ["Lake"])
        #expect(saved.routes.first?.modified == created)
        #expect(saved.deleted.isEmpty)
    }

    @Test func deletionsAreRemembered() {
        let file = URL.temporaryDirectory.appending(path: "routes-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let library = RouteLibrary(store: RouteStore(file: file))
        let route = PlannedRoute(name: "Lake", waypoints: [start])
        library.save(route)
        #expect(library.routes.first?.modified ?? .distantPast >= route.created)
        library.delete(route)
        #expect(library.deleted[route.id] != nil)
        #expect(RouteLibrary(store: RouteStore(file: file)).deleted[route.id] != nil)
        library.adopt([route], deleted: [:])
        #expect(library.routes.map(\.id) == [route.id])
        #expect(library.deleted.isEmpty)
    }
}

@Suite struct PreferencesSyncTests {
    @Test func adoptedSettingsKeepWhatBelongsToTheDevice() {
        let suite = "sync-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = Preferences(defaults: defaults)
        preferences.settings.exportsToCalendar = true
        let changed = preferences.modified
        #expect(changed > .distantPast)
        var shared = Settings()
        shared.density = .dense
        shared.exportsToCalendar = false
        let then = Date(timeIntervalSinceReferenceDate: 815_000_000)
        preferences.adopt(shared, modified: then)
        #expect(preferences.settings.density == .dense)
        #expect(preferences.settings.exportsToCalendar)
        #expect(preferences.modified == then)
        #expect(Preferences(defaults: defaults).modified == then)
    }
}

@Suite struct DeviceSyncTests {
    @Test func syncAdoptsWhatIsNewer() async {
        let routes = RouteLibrary(store: nil)
        let suite = "device-sync-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = Preferences(defaults: defaults)
        let remote = PlannedRoute(name: "From the Mac", waypoints: [])
        let dense = {
            var settings = Settings()
            settings.density = .dense
            return settings
        }()
        let sync = DeviceSync(
            routes: routes, preferences: preferences, folderName: "Shared"
        ) { local in
            local.merged(
                with: SharedState(routes: [remote], settings: dense, settingsModified: .now))
        }
        await sync.sync()
        #expect(routes.routes.map(\.name) == ["From the Mac"])
        #expect(preferences.settings.density == .dense)
        #expect(sync.lastSynced != nil)
        #expect(sync.problem == nil)
    }

    @Test func withoutAFolderOrInTheDemoNothingHappens() async {
        let routes = RouteLibrary(store: nil)
        let none = DeviceSync(routes: routes, preferences: .shared, folderName: nil) { _ in
            Issue.record("synced without a folder")
            return SharedState()
        }
        await none.sync()
        let demo = DeviceSync(
            routes: routes, preferences: .shared, isEnabled: false, folderName: "Shared"
        ) { _ in
            Issue.record("synced in the demo")
            return SharedState()
        }
        await demo.sync()
        #expect(demo.folderName == nil)
    }

    @Test func aFailureIsShown() async {
        let sync = DeviceSync(
            routes: RouteLibrary(store: nil), preferences: .shared, folderName: "Shared"
        ) { _ in throw Problem.offline }
        await sync.sync()
        #expect(sync.problem == .offline)
        #expect(sync.lastSynced == nil)
    }
}
