import GCPAPISync
import SwiftUI

/// The tabs of the signed-in app.
enum AppTab: String {
    /// The dashboard of a wide window, on the iPad and the Mac.
    case dashboard
    case health
    case activities
    case training
    case routes
    case settings
}

extension EnvironmentValues {
    /// Whether to show data densely: smaller charts, more tiles a row, compact lists.
    @Entry var isDense = false
}

/// The signed-in app: the health summary, activities, training and settings, each in its own
/// tab.
struct MainView: View {
    @State private var health: HealthModel
    @State private var training: TrainingModel
    @State private var export: DataExport
    @State private var routes: RouteLibrary
    @State private var deviceSync: DeviceSync
    /// Whether loaded data may leave the app: not in the demo.
    private let exportsData: Bool
    @SceneStorage("selectedTab") private var tab = AppTab.dashboard
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var sizeClass
    private let preferences = Preferences.shared

    /// The app for `client`, opening with what `snapshots` saved last time.
    init(client: GarminClient, snapshots: SnapshotStore? = nil, recordings: RecordingCache? = nil) {
        let training = TrainingModel(client: client, store: snapshots, recordings: recordings)
        training.analysis = Preferences.shared.settings.analysis
        _health = State(initialValue: HealthModel(client: client, store: snapshots))
        _training = State(initialValue: training)
        _export = State(initialValue: DataExport(client: client))
        let routes = RouteLibrary(store: snapshots == nil ? nil : .standard)
        _routes = State(initialValue: routes)
        _deviceSync = State(
            initialValue: DeviceSync(
                routes: routes, preferences: .shared, isEnabled: snapshots != nil))
        exportsData = snapshots != nil
    }

    var body: some View {
        TabView(selection: selection) {
            if isWide {
                Tab("Dashboard", systemImage: "rectangle.split.3x1", value: .dashboard) {
                    DeskView(training: training, health: health) { tab = .settings }
                }
            }
            // A wide window's dashboard shows the summary's metrics too.
            if !isWide {
                Tab("Summary", systemImage: "heart.text.square", value: .health) {
                    WeekView(model: health)
                }
            }
            Tab("Activities", systemImage: "figure.run", value: .activities) {
                ActivitiesView(model: training)
            }
            Tab("Training", systemImage: "chart.line.uptrend.xyaxis", value: .training) {
                TrainingView(model: training)
            }
            Tab("Routes", systemImage: RoutesView.symbol, value: .routes) {
                RoutesView(
                    library: routes, home: home, usualSpeed: usualRunningSpeed,
                    myRoutes: myRoutes, loadMyRoutes: loadMyRoutes)
            }
            Tab("Settings", systemImage: "gearshape", value: .settings) {
                SettingsView(lastUpdated: health.lastUpdated, export: export)
            }
            // A wide window's top tab bar has no room for it in every language: the sidebar and
            // the dashboard's toolbar open it there.
            .defaultVisibility(isWide ? .hidden : .automatic, for: .tabBar)
        }
        // A tab bar on the iPhone, a sidebar on the iPad and the Mac.
        .tabViewStyle(.sidebarAdaptable)
        // Units change every number; drawing everything again picks them up.
        .id(preferences.settings.units)
        .tabBarMinimizeBehavior(.onScrollDown)
        .tint(ColorRole.accent.color)
        // Lists and forms on the plain page, like every other screen.
        .scrollContentBackground(.hidden)
        .background(Color.page)
        .environment(\.isDense, preferences.isDense)
        .onChange(of: preferences.settings.units) {
            training.resetTracks()
        }
        .onChange(of: preferences.settings.analysis) { _, analysis in
            training.analysis = analysis
            Task { await training.load() }
        }
        .onChange(of: preferences.settings.weekStart) {
            Task { await training.load() }
        }
        // After every sync, the export folder and the calendar follow.
        .onChange(of: training.lastUpdated) {
            syncExports()
        }
        // Coming back to the app syncs whatever is more than five minutes old.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                async let week: Void = health.loadIfNeeded(maxAge: 5 * 60)
                async let activities: Void = training.loadIfNeeded(maxAge: 5 * 60)
                async let shared: Void = deviceSync.sync()
                _ = await (week, activities, shared)
            }
        }
        // Routes and settings reach the other devices as soon as they change.
        .onChange(of: routes.routes) { Task { await deviceSync.sync() } }
        .onChange(of: routes.deleted) { Task { await deviceSync.sync() } }
        .onChange(of: preferences.settings) { Task { await deviceSync.sync() } }
        .environment(deviceSync)
    }

    /// Whether the window is wide enough for the dashboard.
    private var isWide: Bool {
        sizeClass == .regular
    }

    /// The selected tab: a wide window has the dashboard instead of the summary, a narrow one
    /// the summary instead of the dashboard.
    private var selection: Binding<AppTab> {
        Binding {
            switch tab {
            case .dashboard where !isWide: .health
            case .health where isWide: .dashboard
            default: tab
            }
        } set: {
            tab = $0
        }
    }

    /// Where the latest activity with GPS started: where new routes begin.
    private var home: GeoPoint? {
        guard case .loaded(let data) = training.phase else { return nil }
        return data.history.lazy.compactMap(\.startPoint).first
    }

    /// The activities of the last 60 days with a route.
    private var recentWithRoutes: [Workout] {
        guard case .loaded(let data) = training.phase, let last = data.loadHistory.last?.date
        else { return [] }
        return data.history.filter { $0.startPoint != nil && $0.date > last.adding(days: -60) }
    }

    /// Their routes, as far as they are loaded: where you usually go, to plan along.
    private var myRoutes: [[GeoPoint]] {
        recentWithRoutes.compactMap { workout in
            training.route(of: workout)?.map {
                GeoPoint(latitude: $0.latitude, longitude: $0.longitude)
            }
        }
    }

    private func loadMyRoutes() async {
        await training.loadTracks(for: recentWithRoutes)
    }

    /// The median speed of the recent runs, for estimating how long a route takes.
    private var usualRunningSpeed: Double? {
        guard case .loaded(let data) = training.phase else { return nil }
        let runs = data.workouts.filter { $0.sport == .running }
        let speeds = runs.compactMap(\.averageSpeed).sorted()
        return speeds.isEmpty ? nil : speeds[speeds.count / 2]
    }

    private func syncExports() {
        guard exportsData, case .loaded(let data) = training.phase else { return }
        let days = health.histories.values.max { $0.days.count < $1.days.count }?.days ?? []
        export.sync(
            days: days, workouts: data.history, folder: FolderSync(),
            calendar: preferences.settings.exportsToCalendar ? CalendarSync() : nil)
    }
}
