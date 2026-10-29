import GCPAPISync
import SwiftUI

/// The signed-in screen: the last seven days of health data.
struct WeekView: View {
    let model: HealthModel
    @Namespace private var cardTransition
    @Environment(Session.self) private var session

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Last 7 Days")
                .navigationDestination(for: Route.self) { route in
                    Group {
                        switch route {
                        case .overview: OverviewDetailView(model: model)
                        case .metric(let metric): MetricDetailView(metric: metric, model: model)
                        }
                    }
                    .navigationTransition(.zoom(sourceID: route, in: cardTransition))
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        SettingsButton(lastUpdated: model.lastUpdated)
                    }
                }
                .task { await model.loadIfNeeded() }
                .refreshable { await model.load() }
        }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .loading:
            DashboardView(history: .sample(endingOn: .today()), transition: cardTransition)
                .redacted(reason: .placeholder)
                .allowsHitTesting(false)
                .accessibilityLabel("Loading")
        case .loaded(let week):
            DashboardView(
                history: week, refreshProblem: model.refreshProblem, transition: cardTransition)
        case .failed(let problem):
            ContentUnavailableView {
                Label(problem.title, systemImage: problem.symbol)
            } description: {
                Text(problem.message)
            } actions: {
                Button("Try Again") {
                    Task { await model.load() }
                }
                .buttonStyle(.glassProminent)
                if problem == .keyRejected {
                    Button("Use a Different Key", role: .destructive) { session.signOut() }
                }
            }
        }
    }
}

#Preview("Loaded") {
    WeekView(model: HealthModel { end, days in .sample(endingOn: end, days: days) })
        .environment(Session.preview)
}

#Preview("Failed") {
    WeekView(model: HealthModel { _, _ in throw Problem.offline })
        .environment(Session.preview)
}
