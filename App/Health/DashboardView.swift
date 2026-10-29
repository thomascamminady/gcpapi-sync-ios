import GCPAPISync
import SwiftUI
import UIKit

/// The week at a glance: one card per metric, each opening its detail screen.
struct DashboardView: View {
    let history: HealthHistory
    var refreshProblem: Problem?
    let transition: Namespace.ID

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                if let refreshProblem {
                    ProblemBanner(problem: refreshProblem)
                }
                ForEach(Metric.allCases) { metric in
                    NavigationLink(value: metric) {
                        MetricCard(metric: metric, history: history)
                    }
                    .buttonStyle(.plain)
                    .matchedTransitionSource(id: metric, in: transition)
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
