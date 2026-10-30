import GCPAPISync
import SwiftUI
import UIKit

/// A screen the dashboard opens.
enum Route: Hashable {
    case overview
    case metric(Metric)
}

/// The week at a glance: a tile per metric and the trends, each opening its detail screen.
struct DashboardView: View {
    let history: HealthHistory
    var refreshProblem: Problem?
    let transition: Namespace.ID

    @Environment(\.isDense) private var isDense

    /// The metrics the user shows tiles for.
    private var tiles: [Metric] {
        Metric.allCases.filter { !Preferences.shared.settings.hiddenTiles.contains($0.rawValue) }
    }

    private var tileGrid: some View {
        LazyVGrid(
            columns: Array(
                repeating: GridItem(.flexible(), spacing: isDense ? 8 : 12),
                count: isDense ? 3 : 2),
            spacing: isDense ? 8 : 12
        ) {
            ForEach(tiles) { metric in
                NavigationLink(value: Route.metric(metric)) {
                    SummaryTile(metric: metric, history: history)
                }
                .buttonStyle(.plain)
                .matchedTransitionSource(id: Route.metric(metric), in: transition)
            }
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: isDense ? 10 : 16) {
                if let refreshProblem {
                    ProblemBanner(problem: refreshProblem)
                }
                tileGrid
                if Preferences.shared.settings.showsTrends {
                    NavigationLink(value: Route.overview) {
                        OverviewCard(history: history)
                    }
                    .buttonStyle(.plain)
                    .matchedTransitionSource(id: Route.overview, in: transition)
                }
                Text("Data from Garmin Connect. Not affiliated with Garmin.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical)
            }
            .padding(.horizontal)
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }
}

/// A notice above the cards when refreshing failed.
struct ProblemBanner: View {
    let problem: Problem

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(problem.title).font(.subheadline.weight(.semibold))
                Text(problem.message).font(.footnote).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: problem.symbol).foregroundStyle(.orange)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.orange.opacity(0.12), in: .rect(cornerRadius: 18))
    }
}

#Preview {
    @Previewable @Namespace var transition
    NavigationStack {
        DashboardView(history: .sample(endingOn: .today()), transition: transition)
    }
}
