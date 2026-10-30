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
    @SceneStorage("selectedTab") private var tab = AppTab.health
    private let preferences = Preferences.shared

    init(client: GarminClient) {
        let training = TrainingModel(client: client)
        training.analysis = Preferences.shared.settings.analysis
        _health = State(initialValue: HealthModel(client: client))
        _training = State(initialValue: training)
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
                SettingsView(lastUpdated: health.lastUpdated)
            }
        }
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
    }
}
