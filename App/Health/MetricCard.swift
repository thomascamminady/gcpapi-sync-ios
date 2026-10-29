import SwiftUI
import UIKit

/// A dashboard card: a metric's name, its headline value, context, and a chart.
struct MetricCard<Chart: View>: View {
    let title: String
    let symbol: String
    let tint: Color
    let value: String
    var unit: String?
    let detail: String
    @ViewBuilder let chart: Chart

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value)
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .contentTransition(.numericText())
                    if let unit {
                        Text(unit)
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            chart
                .frame(height: 150)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 26))
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
