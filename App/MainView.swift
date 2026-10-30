import GCPAPISync
import SwiftUI

/// The tabs of the signed-in app.
enum AppTab: String {
    case health
    case activities
    case training
}

/// The signed-in app: the health summary, activities and training, each in its own tab.
struct MainView: View {
    @State private var health: HealthModel
    @State private var training: TrainingModel
    @SceneStorage("selectedTab") private var tab = AppTab.health

    init(client: GarminClient) {
        _health = State(initialValue: HealthModel(client: client))
        _training = State(initialValue: TrainingModel(client: client))
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
        }
        .tabBarMinimizeBehavior(.onScrollDown)
    }
}
