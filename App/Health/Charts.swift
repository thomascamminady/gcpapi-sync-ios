import Charts
import SwiftUI

extension View {
    /// Weekday labels under the bars and a light grid, shared by every dashboard chart.
    func weekChartStyle() -> some View {
        chartXAxis {
            AxisMarks(values: .stride(by: .day)) { _ in
                AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
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

struct StepsChart: View {
    let days: [DayHealth]

    private var goal: Int? { days.compactMap(\.stepGoal).last }

    var body: some View {
        Chart {
            ForEach(days) { day in
                if let steps = day.steps {
                    BarMark(
                        x: .value("Day", day.start, unit: .day),
                        y: .value("Steps", steps),
                        width: .ratio(0.55)
                    )
                    .foregroundStyle(steps >= (day.stepGoal ?? .max) ? Color.green : Color.teal)
                    .clipShape(.capsule)
                }
            }
            if let goal {
                RuleMark(y: .value("Goal", goal))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(.secondary)
            }
        }
        .weekChartStyle()
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

    var body: some View {
        Chart {
            ForEach(days) { day in
                if let night = day.sleep {
                    ForEach(SleepStage.allCases) { stage in
                        BarMark(
                            x: .value("Day", day.start, unit: .day),
                            y: .value("Hours", stage.hours(of: night)),
                            width: .ratio(0.55)
                        )
                        .foregroundStyle(by: .value("Stage", stage.label))
                    }
                }
            }
        }
        .chartForegroundStyleScale(
            domain: SleepStage.allCases.map(\.label), range: SleepStage.allCases.map(\.color)
        )
        .chartLegend(position: .bottom, spacing: 8)
        .weekChartStyle()
    }
}

/// A line through one value per day, for resting heart rate and HRV.
struct TrendChart: View {
    let days: [DayHealth]
    let metric: KeyPath<DayHealth, Int?>
    let label: String
    let tint: Color

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
                    PointMark(x: .value("Day", day.start, unit: .day), y: .value(label, value))
                        .foregroundStyle(tint)
                        .symbolSize(40)
                }
            }
        }
        .chartYScale(domain: lowerBound...upperBound)
        .weekChartStyle()
    }

    private var values: [Int] { days.compactMap { $0[keyPath: metric] } }
    private var lowerBound: Int { max(0, (values.min() ?? 0) - 5) }
    private var upperBound: Int { (values.max() ?? 10) + 5 }
}

struct BodyBatteryChart: View {
    let days: [DayHealth]

    var body: some View {
        Chart {
            ForEach(days) { day in
                if let low = day.bodyBatteryLow, let high = day.bodyBatteryHigh {
                    BarMark(
                        x: .value("Day", day.start, unit: .day),
                        yStart: .value("Lowest", low),
                        yEnd: .value("Highest", high),
                        width: .ratio(0.4)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.mint, .green], startPoint: .bottom, endPoint: .top)
                    )
                    .clipShape(.capsule)
                }
            }
        }
        .chartYScale(domain: 0...100)
        .weekChartStyle()
    }
}

struct StressChart: View {
    let days: [DayHealth]

    var body: some View {
        Chart {
            ForEach(days) { day in
                if let stress = day.stress {
                    BarMark(
                        x: .value("Day", day.start, unit: .day),
                        y: .value("Stress", stress),
                        width: .ratio(0.55)
                    )
                    .foregroundStyle(Format.stressColor(stress))
                    .clipShape(.capsule)
                }
            }
        }
        .chartYScale(domain: 0...100)
        .weekChartStyle()
    }
}

struct IntensityChart: View {
    let days: [DayHealth]

    var body: some View {
        Chart {
            ForEach(days) { day in
                if let minutes = day.intensityMinutes {
                    BarMark(
                        x: .value("Day", day.start, unit: .day),
                        y: .value("Minutes", minutes),
                        width: .ratio(0.55)
                    )
                    .foregroundStyle(Color.orange)
                    .clipShape(.capsule)
                }
            }
        }
        .weekChartStyle()
    }
}
