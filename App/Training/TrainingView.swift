import GCPAPISync
import SwiftUI
import UIKit

/// A screen the training tab opens.
enum TrainingRoute: Hashable {
    case load
    case activities
    case workout(Workout)
}

/// The training tab: load, volume and recent activities.
struct TrainingView: View {
    let model: TrainingModel
    @Namespace private var transition

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Training")
                .navigationDestination(for: TrainingRoute.self) { route in
                    if case .loaded(let data) = model.phase {
                        destination(route, data: data)
                    }
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

    @ViewBuilder
    private func destination(_ route: TrainingRoute, data: TrainingData) -> some View {
        switch route {
        case .load:
            TrainingLoadDetailView(days: data.load)
                .navigationTransition(.zoom(sourceID: route, in: transition))
        case .activities:
            ActivityListView(data: data)
        case .workout(let workout):
            WorkoutDetailView(workout: workout, zones: data.heartRateZones(for: workout.sport))
        }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .loading:
            TrainingDashboard(data: .sample(endingOn: .today()), transition: transition)
                .redacted(reason: .placeholder)
                .allowsHitTesting(false)
                .accessibilityLabel("Loading")
        case .loaded(let data):
            TrainingDashboard(
                data: data, refreshProblem: model.refreshProblem, transition: transition)
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
            }
        }
    }
}

/// Load, volume and the latest activities.
struct TrainingDashboard: View {
    let data: TrainingData
    var refreshProblem: Problem?
    let transition: Namespace.ID

    private var recent: [Workout] { Array(data.workouts.prefix(5)) }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                if let refreshProblem {
                    ProblemBanner(problem: refreshProblem)
                }
                NavigationLink(value: TrainingRoute.load) {
                    LoadCard(days: data.load)
                }
                .buttonStyle(.plain)
                .matchedTransitionSource(id: TrainingRoute.load, in: transition)
                VolumeCard(weeks: data.weeks)
                activities
                Text("Training load, training effect and zones are Garmin's.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical)
            }
            .padding(.horizontal)
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private var activities: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Recent Activities").font(.title3.weight(.bold))
                Spacer()
                NavigationLink("Show All", value: TrainingRoute.activities)
            }
            if recent.isEmpty {
                Text("No activities in the last 90 days.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardStyle()
            } else {
                VStack(spacing: 0) {
                    ForEach(recent) { workout in
                        NavigationLink(value: TrainingRoute.workout(workout)) {
                            WorkoutRow(workout: workout)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                        if workout.id != recent.last?.id {
                            Divider()
                        }
                    }
                }
                .padding(.horizontal, 16)
                .background(
                    Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
            }
        }
        .padding(.top, 4)
    }
}

#Preview {
    TrainingView(model: TrainingModel { end in .sample(endingOn: end) })
        .environment(Session.preview)
}
