import SwiftUI
import UIKit

/// A dashboard card: a metric's name, its headline value, context, and a chart.
struct MetricCard: View {
    let metric: Metric
    let history: HealthHistory

    var body: some View {
        let summary = metric.summary(of: history)
        VStack(alignment: .leading, spacing: 14) {
            header
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(summary.value)
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .contentTransition(.numericText())
                    if let unit = summary.unit {
                        Text(unit)
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if metric == .hrv, let status = Format.hrvStatus(history.latest(\.hrvStatus)) {
                        StatusBadge(label: status.label, color: status.color)
                    }
                }
                Text(summary.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            MetricChart(metric: metric, days: history.days)
                .frame(height: 150)
                .allowsHitTesting(false)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 26))
        .contentShape(.rect(cornerRadius: 26))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Shows details")
    }

    private var header: some View {
        HStack {
            Label(metric.title, systemImage: metric.symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(metric.tint)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
    }
}

/// A short status label in a tinted capsule.
struct StatusBadge: View {
    let label: String
    let color: Color

    var body: some View {
        Text(label)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .foregroundStyle(color)
            .background(color.opacity(0.15), in: .capsule)
    }
}
