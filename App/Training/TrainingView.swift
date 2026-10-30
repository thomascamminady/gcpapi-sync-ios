import GCPAPISync
import SwiftUI
import UIKit

/// A screen the training tab opens.
enum TrainingRoute: Hashable {
    case load
    case recovery
}

/// The training tab: load, recovery and volume.
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
                .navigationSubtitle(SyncStatus.text(model.lastUpdated))
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
        case .recovery:
            if case .loaded(let response) = model.recovery {
                RecoveryDetailView(response: response)
                    .navigationTransition(.zoom(sourceID: route, in: transition))
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .loading:
            TrainingDashboard(
                data: .sample(endingOn: .today()), recovery: .loading, transition: transition
            )
            .redacted(reason: .placeholder)
            .allowsHitTesting(false)
            .accessibilityLabel("Loading")
        case .loaded(let data):
            TrainingDashboard(
                data: data, recovery: model.recovery, refreshProblem: model.refreshProblem,
                transition: transition)
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

/// Load, recovery and volume.
struct TrainingDashboard: View {
    let data: TrainingData
    let recovery: TrainingModel.RecoveryPhase
    var refreshProblem: Problem?
    let transition: Namespace.ID
    @Environment(\.isDense) private var isDense

    var body: some View {
        ScrollView {
            LazyVStack(spacing: isDense ? 10 : 16) {
                if let refreshProblem {
                    ProblemBanner(problem: refreshProblem)
                }
                NavigationLink(value: TrainingRoute.load) {
                    LoadCard(days: data.load)
                }
                .buttonStyle(.plain)
                .matchedTransitionSource(id: TrainingRoute.load, in: transition)
                recoveryCard
                VolumeCard(weeks: data.weeks)
                Text("Training load, training effect and zones are Garmin's.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical)
            }
            .padding(.horizontal)
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }

    @ViewBuilder private var recoveryCard: some View {
        if case .loaded(let response) = recovery, response.isSufficient {
            NavigationLink(value: TrainingRoute.recovery) {
                RecoveryCard(phase: recovery)
            }
            .buttonStyle(.plain)
            .matchedTransitionSource(id: TrainingRoute.recovery, in: transition)
        } else {
            RecoveryCard(phase: recovery)
        }
    }
}

#Preview {
    TrainingView(
        model: TrainingModel(
            fetch: { end, _ in .sample(endingOn: end) },
            fetchHealth: { end, days in .sample(endingOn: end, days: days) })
    )
    .environment(Session.preview)
}
