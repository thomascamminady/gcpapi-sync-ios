import GCPAPISync
import SwiftUI

/// The tabs of the signed-in app.
enum AppTab: String {
    case health
    case activities
    case training
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
    /// Whether loaded data may leave the app: not in the demo.
    private let exportsData: Bool
    @SceneStorage("selectedTab") private var tab = AppTab.health
    @Environment(\.scenePhase) private var scenePhase
    private let preferences = Preferences.shared

    /// The app for `client`, opening with what `snapshots` saved last time.
    init(client: GarminClient, snapshots: SnapshotStore? = nil, recordings: RecordingCache? = nil) {
        let training = TrainingModel(client: client, store: snapshots, recordings: recordings)
        training.analysis = Preferences.shared.settings.analysis
        _health = State(initialValue: HealthModel(client: client, store: snapshots))
        _training = State(initialValue: training)
        _export = State(initialValue: DataExport(client: client))
        exportsData = snapshots != nil
    }

    var body: some View {
        TabView(selection: $tab) {
            Tab("Summary", systemImage: "heart.text.square", value: .health) {
                WeekView(model: health)
            }
            Tab("Activities", systemImage: "figure.run", value: .activities) {
                ActivitiesView(model: training)
            }
            Tab("Training", systemImage: "chart.line.uptrend.xyaxis", value: .training) {
                TrainingView(model: training)
            }
            Tab("Settings", systemImage: "gearshape", value: .settings) {
                SettingsView(lastUpdated: health.lastUpdated, export: export)
            }
        }
        // A tab bar on the iPhone, a sidebar on the iPad and the Mac.
        .tabViewStyle(.sidebarAdaptable)
        // Units change every number; drawing everything again picks them up.
        .id(preferences.settings.units)
        .tabBarMinimizeBehavior(.onScrollDown)
        .tint(ColorRole.accent.color)
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
                _ = await (week, activities)
            }
        }
    }

    private func syncExports() {
        guard exportsData, case .loaded(let data) = training.phase else { return }
        let days = health.histories.values.max { $0.days.count < $1.days.count }?.days ?? []
        export.sync(
            days: days, workouts: data.history, folder: FolderSync(),
            calendar: preferences.settings.exportsToCalendar ? CalendarSync() : nil)
    }
}
