import Charts
import GCPAPISync
import SwiftUI
import UIKit

/// The metrics the overview draws on one chart. Their units differ, so each is scaled to
/// 0...1 over the days shown: 0 is its lowest value in the range and 1 its highest.
nonisolated enum OverviewMetric: String, CaseIterable, Identifiable, Sendable {
    case hrv
    case restingHeartRate
    case sleepScore
    case stress
    case vo2max

    var id: Self { self }

    var title: String {
        switch self {
        case .hrv: String(localized: "HRV")
        case .restingHeartRate: String(localized: "Resting HR")
        case .sleepScore: String(localized: "Sleep Score")
        case .stress: String(localized: "Stress")
        case .vo2max: String(localized: "VO2max")
        }
    }

    /// The color of the metric the line shows.
    @MainActor var color: Color { metric.tint }

    /// The metric this line shows, whose color it has.
    var metric: Metric {
        switch self {
        case .hrv: .hrv
        case .restingHeartRate: .restingHeartRate
        case .sleepScore: .sleep
        case .stress: .stress
        case .vo2max: .vo2max
        }
    }

    /// A shape for each metric, so the lines are told apart by more than their color.
    var shape: BasicChartSymbolShape {
        switch self {
        case .hrv: .circle
        case .restingHeartRate: .square
        case .sleepScore: .triangle
        case .stress: .diamond
        case .vo2max: .pentagon
        }
    }

    /// The SF Symbol matching ``shape``, for legends.
    var symbol: String {
        switch self {
        case .hrv: "circle.fill"
        case .restingHeartRate: "square.fill"
        case .sleepScore: "triangle.fill"
        case .stress: "diamond.fill"
        case .vo2max: "pentagon.fill"
        }
    }

    /// Whether lower values are the better ones.
    var lowerIsBetter: Bool {
        self == .restingHeartRate || self == .stress
    }

    func value(of day: DayHealth) -> Double? {
        switch self {
        case .hrv: day.hrv.map(Double.init)
        case .restingHeartRate: day.restingHeartRate.map(Double.init)
        case .sleepScore: day.sleep?.score.map(Double.init)
        case .stress: day.stress.map(Double.init)
        case .vo2max: day.vo2max
        }
    }

    /// `value` with its unit.
    func formatted(_ value: Double?) -> String {
        guard let value else { return "–" }
        return switch self {
        case .hrv: "\(Format.number(Int(value.rounded()))) ms"
        case .restingHeartRate: "\(Format.number(Int(value.rounded()))) bpm"
        case .sleepScore, .stress: Format.number(Int(value.rounded()))
        case .vo2max: "\(Format.decimal(value)) ml/kg/min"
        }
    }

    /// The days that have a value, scaled so the lowest is 0 and the highest 1.
    ///
    /// With `averaging` above 1, a day's value is the mean of the `averaging` days ending on
    /// it, and the first `averaging - 1` days only lead into those means, so that every value
    /// averages a full window. With `higherIsBetter`, metrics that are better when lower are
    /// flipped, so 1 is always the best day. A metric that never changes sits at 0.5.
    func scaled(
        _ days: [DayHealth], averaging: Int = 1, higherIsBetter: Bool = false
    )
        -> [ScaledValue]
    {
        let raw = days.map(value(of:))
        let shown = days.indices.dropFirst(max(0, averaging - 1))
        let values = shown.compactMap { index -> (date: GarminDate, value: Double)? in
            guard raw[index] != nil else { return nil }
            let window = raw[max(0, index + 1 - averaging)...index].compactMap(\.self)
            return (days[index].date, window.reduce(0, +) / Double(window.count))
        }
        guard let low = values.map(\.value).min(), let high = values.map(\.value).max() else {
            return []
        }
        let flips = higherIsBetter && lowerIsBetter
        return values.map { item in
            let share = high > low ? (item.value - low) / (high - low) : 0.5
            return ScaledValue(
                date: item.date, value: item.value, scaled: flips ? 1 - share : share)
        }
    }
}

/// A metric's value on one day, and where it lies within the range shown.
nonisolated struct ScaledValue: Hashable, Sendable {
    let date: GarminDate
    let value: Double
    let scaled: Double
}

/// HRV, resting heart rate, sleep score, stress and VO2max on one chart, each scaled to 0...1.
struct OverviewChart: View {
    let days: [DayHealth]
    var metrics: [OverviewMetric] = OverviewMetric.allCases
    var averaging = 1
    var higherIsBetter = false
    var selected: Date?

    var body: some View {
        Chart {
            ForEach(metrics) { metric in
                let points = metric.scaled(
                    days, averaging: averaging, higherIsBetter: higherIsBetter)
                ForEach(points, id: \.date) { point in
                    LineMark(
                        x: .value("Day", point.date.startOfDay(in: .current), unit: .day),
                        y: .value("Scaled", point.scaled),
                        series: .value("Metric", metric.title)
                    )
                    .foregroundStyle(by: .value("Metric", metric.title))
                    .symbol(by: .value("Metric", metric.title))
                    .symbolSize(days.count <= 10 ? 50 : 0)
                    // Monotone curves never overshoot 0...1.
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }
                if let point = points.first(where: { $0.date.startOfDay(in: .current) == selected })
                {
                    PointMark(
                        x: .value("Day", point.date.startOfDay(in: .current), unit: .day),
                        y: .value("Scaled", point.scaled)
                    )
                    .foregroundStyle(by: .value("Metric", metric.title))
                    .symbol(by: .value("Metric", metric.title))
                    .symbolSize(90)
                }
            }
            if let selected {
                SelectionRule(date: selected)
            }
        }
        // A fixed scale keeps every metric's color and shape when others are hidden.
        .chartForegroundStyleScale(
            domain: OverviewMetric.allCases.map(\.title),
            range: OverviewMetric.allCases.map(\.color)
        )
        .chartSymbolScale(
            domain: OverviewMetric.allCases.map(\.title),
            range: OverviewMetric.allCases.map(\.shape)
        )
        .chartLegend(.hidden)
        .chartYScale(domain: 0...1)
        .dayChartStyle(count: days.count)
    }
}

/// A metric's shape and color with its name.
struct OverviewLegendLabel: View {
    let metric: OverviewMetric

    var body: some View {
        Label {
            Text(metric.title)
        } icon: {
            Image(systemName: metric.symbol)
                .font(.system(size: 9))
                .foregroundStyle(metric.color)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .labelStyle(.titleAndIcon)
    }
}

/// The dashboard's first card: the week's overview chart.
struct OverviewCard: View {
    let history: HealthHistory

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Trends", systemImage: "chart.xyaxis.line")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.tint)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            Text("Each metric scaled from its lowest (0) to its highest (1) this week")
                .font(.footnote)
                .foregroundStyle(.secondary)
            OverviewChart(days: history.days)
                .chartHeight(170)
                .allowsHitTesting(false)
            ViewThatFits {
                HStack(spacing: 12) {
                    ForEach(OverviewMetric.allCases) { OverviewLegendLabel(metric: $0) }
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), alignment: .leading)]) {
                    ForEach(OverviewMetric.allCases) { OverviewLegendLabel(metric: $0) }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 26))
        .contentShape(.rect(cornerRadius: 26))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Shows details")
    }
}
