import Charts
import SwiftUI

extension View {
    /// Day labels that fit `count` days (weekdays for a week, dates for longer ranges) and a
    /// light grid, shared by every chart.
    func dayChartStyle(count: Int) -> some View {
        chartXAxis {
            if count <= 10 {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
                }
            } else if count <= 45 {
                AxisMarks(values: .stride(by: .weekOfYear)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                }
            } else {
                AxisMarks(values: .stride(by: .month)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month(.abbreviated))
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine()
                AxisValueLabel()
            }
        }
    }
}

/// The chart of `metric` over `days`, with `selected` highlighted.
struct MetricChart: View {
    let metric: Metric
    let days: [DayHealth]
    var selected: Date?

    var body: some View {
        switch metric {
        case .steps: StepsChart(days: days, selected: selected)
        case .sleep: SleepChart(days: days, selected: selected)
        case .restingHeartRate:
            TrendChart(
                days: days, metric: \.restingHeartRate, label: metric.title, tint: metric.tint,
                selected: selected)
        case .hrv:
            TrendChart(
                days: days, metric: \.hrv, label: metric.title, tint: metric.tint,
                selected: selected)
        case .bodyBattery: BodyBatteryChart(days: days, selected: selected)
        case .stress: StressChart(days: days, selected: selected)
        case .intensityMinutes: IntensityChart(days: days, selected: selected)
        }
    }
}

/// A vertical rule marking the selected day.
private struct SelectionRule: ChartContent {
    let date: Date

    var body: some ChartContent {
        RuleMark(x: .value("Selected", date, unit: .day))
            .foregroundStyle(Color.secondary.opacity(0.35))
            .lineStyle(StrokeStyle(lineWidth: 2))
    }
}

/// Bars get relatively wider as the range gets longer, so they stay visible.
private func barWidth(_ count: Int) -> MarkDimension {
    count <= 10 ? .ratio(0.55) : .ratio(0.7)
}

struct StepsChart: View {
    let days: [DayHealth]
    var selected: Date?

    var body: some View {
        Chart {
            ForEach(days) { day in
                if let steps = day.steps {
                    BarMark(
                        x: .value("Day", day.start, unit: .day),
                        y: .value("Steps", steps),
                        width: barWidth(days.count)
                    )
                    .foregroundStyle(steps >= (day.stepGoal ?? .max) ? Color.green : Color.teal)
                    .clipShape(.capsule)
                }
                // Garmin's goal adapts every day, so each day gets its own goal mark.
                if let goal = day.stepGoal {
                    RectangleMark(
                        x: .value("Day", day.start, unit: .day),
                        y: .value("Goal", goal),
                        width: barWidth(days.count),
                        height: 2
                    )
                    .foregroundStyle(Color.primary.opacity(0.45))
                }
            }
            if let selected {
                SelectionRule(date: selected)
            }
        }
        .dayChartStyle(count: days.count)
    }
}

/// Sleep stages, from the deepest to awake.
enum SleepStage: String, CaseIterable, Identifiable {
    case deep, light, rem, awake

    var id: Self { self }

    var label: String {
        switch self {
        case .deep: String(localized: "Deep")
        case .light: String(localized: "Light")
        case .rem: String(localized: "REM")
        case .awake: String(localized: "Awake")
        }
    }

    var color: Color {
        switch self {
        case .deep: .indigo
        case .light: .blue
        case .rem: .cyan
        case .awake: .pink
        }
    }

    func hours(of night: SleepNight) -> Double {
        let seconds =
            switch self {
            case .deep: night.deep
            case .light: night.light
            case .rem: night.rem
            case .awake: night.awake
            }
        return Double(seconds) / 3600
    }
}

struct SleepChart: View {
    let days: [DayHealth]
    var selected: Date?

    var body: some View {
        Chart {
            ForEach(days) { day in
                if let night = day.sleep {
                    ForEach(SleepStage.allCases) { stage in
                        BarMark(
                            x: .value("Day", day.start, unit: .day),
                            y: .value("Hours", stage.hours(of: night)),
                            width: barWidth(days.count)
                        )
                        .foregroundStyle(by: .value("Stage", stage.label))
                    }
                }
            }
            if let selected {
                SelectionRule(date: selected)
            }
        }
        .chartForegroundStyleScale(
            domain: SleepStage.allCases.map(\.label), range: SleepStage.allCases.map(\.color)
        )
        .chartLegend(position: .bottom, spacing: 8)
        .dayChartStyle(count: days.count)
    }
}

/// A line through one value per day, for resting heart rate and HRV.
struct TrendChart: View {
    let days: [DayHealth]
    let metric: KeyPath<DayHealth, Int?>
    let label: String
    let tint: Color
    var selected: Date?

    var body: some View {
        Chart {
            ForEach(days) { day in
                if let value = day[keyPath: metric] {
                    AreaMark(
                        x: .value("Day", day.start, unit: .day),
                        yStart: .value(label, lowerBound),
                        yEnd: .value(label, value)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [tint.opacity(0.25), tint.opacity(0)], startPoint: .top,
                            endPoint: .bottom))
                    LineMark(x: .value("Day", day.start, unit: .day), y: .value(label, value))
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                        .foregroundStyle(tint)
                    if days.count <= 31 {
                        PointMark(x: .value("Day", day.start, unit: .day), y: .value(label, value))
                            .foregroundStyle(tint)
                            .symbolSize(40)
                    }
                }
            }
            if let selected {
                SelectionRule(date: selected)
            }
        }
        .chartYScale(domain: lowerBound...upperBound)
        .dayChartStyle(count: days.count)
    }

    private var values: [Int] { days.compactMap { $0[keyPath: metric] } }
    private var lowerBound: Int { max(0, (values.min() ?? 0) - 5) }
    private var upperBound: Int { (values.max() ?? 10) + 5 }
}

struct BodyBatteryChart: View {
    let days: [DayHealth]
    var selected: Date?

    var body: some View {
        Chart {
            ForEach(days) { day in
                if let low = day.bodyBatteryLow, let high = day.bodyBatteryHigh {
                    BarMark(
                        x: .value("Day", day.start, unit: .day),
                        yStart: .value("Lowest", low),
                        yEnd: .value("Highest", high),
                        width: days.count <= 10 ? .ratio(0.4) : .ratio(0.6)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.mint, .green], startPoint: .bottom, endPoint: .top)
                    )
                    .clipShape(.capsule)
                }
            }
            if let selected {
                SelectionRule(date: selected)
            }
        }
        .chartYScale(domain: 0...100)
        .dayChartStyle(count: days.count)
    }
}

struct StressChart: View {
    let days: [DayHealth]
    var selected: Date?

    var body: some View {
        Chart {
            ForEach(days) { day in
                if let stress = day.stress {
                    BarMark(
                        x: .value("Day", day.start, unit: .day),
                        y: .value("Stress", stress),
                        width: barWidth(days.count)
                    )
                    .foregroundStyle(Format.stressColor(stress))
                    .clipShape(.capsule)
                }
            }
            if let selected {
                SelectionRule(date: selected)
            }
        }
        .chartYScale(domain: 0...100)
        .dayChartStyle(count: days.count)
    }
}

struct IntensityChart: View {
    let days: [DayHealth]
    var selected: Date?

    var body: some View {
        Chart {
            ForEach(days) { day in
                if let minutes = day.intensityMinutes {
                    BarMark(
                        x: .value("Day", day.start, unit: .day),
                        y: .value("Minutes", minutes),
                        width: barWidth(days.count)
                    )
                    .foregroundStyle(Color.orange)
                    .clipShape(.capsule)
                }
            }
            if let selected {
                SelectionRule(date: selected)
            }
        }
        .dayChartStyle(count: days.count)
    }
}
