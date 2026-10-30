import Charts
import GCPAPISync
import SwiftUI
import UIKit

extension Metric {
    /// A name short enough for a tile.
    var shortTitle: String {
        switch self {
        case .restingHeartRate: String(localized: "Resting HR")
        case .hrv: String(localized: "HRV")
        case .intensityMinutes: String(localized: "Intensity")
        default: title
        }
    }

    /// A day's value as a number, for sparklines.
    func number(of day: DayHealth) -> Double? {
        switch self {
        case .steps: day.steps.map(Double.init)
        case .sleep: day.sleep.map { Double($0.total) / 3600 }
        case .restingHeartRate: day.restingHeartRate.map(Double.init)
        case .hrv: day.hrv.map(Double.init)
        case .vo2max: day.vo2max
        case .bodyBattery: day.bodyBatteryHigh.map(Double.init)
        case .stress: day.stress.map(Double.init)
        case .intensityMinutes: day.intensityMinutes.map(Double.init)
        }
    }

    /// Whether the sparkline has bars (amounts) rather than a line (levels).
    var isAmount: Bool {
        [.steps, .sleep, .intensityMinutes].contains(self)
    }

    /// The tile's headline: the latest day's value and when it is from; intensity minutes
    /// count per week, as their goal does.
    func tile(of history: HealthHistory) -> Summary? {
        if self == .intensityMinutes {
            let summary = summary(of: history)
            return Summary(value: summary.value, unit: summary.unit, detail: summary.detail)
        }
        guard let day = history.days.last(where: hasValue) else { return nil }
        return Summary(value: value(of: day), unit: unit, detail: Self.when(day.date, metric: self))
    }

    /// `Today`, `Last night`, `Yesterday` or the weekday.
    static func when(_ date: GarminDate, metric: Metric) -> String {
        let today = GarminDate.today()
        if date == today {
            return [.sleep, .hrv].contains(metric)
                ? String(localized: "Last night") : String(localized: "Today")
        }
        if date == today.adding(days: -1) {
            return String(localized: "Yesterday")
        }
        return date.startOfDay(in: .current).formatted(.dateTime.weekday(.wide))
    }
}

/// A compact tile in the style of the Health app: a metric's latest value and its week.
struct SummaryTile: View {
    let metric: Metric
    let history: HealthHistory
    @Environment(\.isDense) private var isDense

    var body: some View {
        let tile = metric.tile(of: history)
        VStack(alignment: .leading, spacing: 6) {
            header
            Spacer(minLength: 0)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(tile?.value ?? "–")
                    .font(.system(isDense ? .headline : .title2, design: .rounded, weight: .bold))
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                    .contentTransition(.numericText())
                if let unit = tile?.unit {
                    Text(unit)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            HStack(alignment: .bottom) {
                Text(tile?.detail ?? String(localized: "No data"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(isDense ? 1 : 2)
                Spacer(minLength: 4)
                Sparkline(metric: metric, days: history.days)
                    .frame(width: isDense ? 36 : 58, height: isDense ? 18 : 26)
            }
        }
        .padding(isDense ? 9 : 14)
        .frame(maxWidth: .infinity, minHeight: isDense ? 92 : 126, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
        .contentShape(.rect(cornerRadius: 20))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Shows details")
    }

    private var header: some View {
        HStack(spacing: 5) {
            Image(systemName: metric.symbol)
                .accessibilityHidden(true)
            Text(metric.shortTitle)
                .lineLimit(1)
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(metric.tint)
    }
}

/// A metric's last days, without axes.
struct Sparkline: View {
    let metric: Metric
    let days: [DayHealth]

    var body: some View {
        let points = days.compactMap { day in metric.number(of: day).map { (day.start, $0) } }
        let values = points.map(\.1)
        let low = metric.isAmount ? 0 : (values.min() ?? 0)
        let high = max(values.max() ?? 1, low + 1)
        Chart {
            ForEach(points, id: \.0) { date, value in
                if metric.isAmount {
                    BarMark(x: .value("Day", date, unit: .day), y: .value("Value", value))
                        .foregroundStyle(metric.tint.opacity(date == points.last?.0 ? 1 : 0.45))
                        .clipShape(.capsule)
                } else {
                    LineMark(x: .value("Day", date, unit: .day), y: .value("Value", value))
                        .foregroundStyle(metric.tint)
                        .interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                }
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: low...high)
        .accessibilityHidden(true)
    }
}
