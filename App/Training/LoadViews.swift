import Charts
import GCPAPISync
import SwiftUI
import UIKit

/// The colors of the fitness and fatigue lines.
private var fitnessColor: Color { ColorRole.fitness.color }
private var fatigueColor: Color { ColorRole.fatigue.color }

/// The training tab's first card: fitness, fatigue and form over the last 90 days.
struct LoadCard: View {
    let days: [TrainingLoad.Day]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardHeader(
                title: "Training Load", symbol: "chart.line.uptrend.xyaxis", tint: fitnessColor,
                opensDetail: true)
            if let today = days.last {
                LoadSummary(day: today)
            }
            LoadChart(days: days)
                .chartHeight(140)
            FormChart(days: days)
                .chartHeight(90)
        }
        .allowsHitTesting(false)
        .cardStyle()
        .contentShape(.rect(cornerRadius: 26))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Shows details")
    }
}

/// Fitness, fatigue and form of one day, with its form zone.
struct LoadSummary: View {
    let day: TrainingLoad.Day

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            LoadFigure(title: "Fitness", value: day.fitness, color: fitnessColor)
            LoadFigure(title: "Fatigue", value: day.fatigue, color: fatigueColor)
            LoadFigure(title: "Form", value: day.form, signed: true)
            Spacer(minLength: 0)
            if let zone = day.zone {
                FormZoneBadge(zone: zone)
            }
        }
    }
}

/// A number with its name and, for a line in the chart, the line's color.
private struct LoadFigure: View {
    let title: LocalizedStringKey
    let value: Double
    var color: Color?
    var signed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                if let color {
                    Capsule().fill(color).frame(width: 12, height: 3)
                }
                Text(title)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            Text(
                value.formatted(
                    .number.precision(.fractionLength(0)).sign(
                        strategy: signed ? .always() : .automatic))
            )
            .font(.title2.weight(.bold).monospacedDigit())
            .contentTransition(.numericText())
        }
        .fixedSize()
        .accessibilityElement(children: .combine)
    }
}

/// A form zone's name and symbol in a tinted capsule.
struct FormZoneBadge: View {
    let zone: FormZone

    var body: some View {
        Label(zone.title, systemImage: zone.symbol)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .foregroundStyle(zone.color)
            .background(zone.color.opacity(0.15), in: .capsule)
    }
}

/// Fitness and fatigue over `days`.
struct LoadChart: View {
    let days: [TrainingLoad.Day]
    var selected: Date?

    var body: some View {
        Chart {
            ForEach(days) { day in
                let date = day.date.startOfDay(in: .current)
                AreaMark(x: .value("Day", date, unit: .day), y: .value("Fitness", day.fitness))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [fitnessColor.opacity(0.22), fitnessColor.opacity(0)],
                            startPoint: .top, endPoint: .bottom))
                LineMark(
                    x: .value("Day", date, unit: .day), y: .value("Load", day.fitness),
                    series: .value("Series", "fitness")
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(fitnessColor)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                LineMark(
                    x: .value("Day", date, unit: .day), y: .value("Load", day.fatigue),
                    series: .value("Series", "fatigue")
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(fatigueColor)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
            }
            if let selected {
                SelectionRule(date: selected)
            }
        }
        .dayChartStyle(count: days.count)
    }
}

/// Form as a share of fitness over `days`, on the bands of the form zones.
struct FormChart: View {
    let days: [TrainingLoad.Day]
    var selected: Date?

    var body: some View {
        Chart {
            if let first = days.first?.date, let last = days.last?.date {
                ForEach(FormZone.allCases, id: \.self) { zone in
                    RectangleMark(
                        xStart: .value("Start", first.startOfDay(in: .current)),
                        xEnd: .value("End", last.adding(days: 1).startOfDay(in: .current)),
                        yStart: .value("From", zone.band.lowerBound * 100),
                        yEnd: .value("To", zone.band.upperBound * 100)
                    )
                    .foregroundStyle(zone.color.opacity(0.13))
                }
            }
            ForEach(days) { day in
                if let share = day.formShare {
                    LineMark(
                        x: .value("Day", day.date.startOfDay(in: .current), unit: .day),
                        y: .value("Form", max(-50, min(40, share * 100)))
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(Color.primary)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                }
            }
            if let selected {
                SelectionRule(date: selected)
            }
        }
        .chartYScale(domain: -50...40)
        .chartYAxis {
            AxisMarks(position: .leading, values: [-30, 0, 20]) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let percent = value.as(Int.self) {
                        Text("\(percent)%")
                    }
                }
            }
        }
        .dayAxis(count: days.count)
    }
}

/// Daily training load as bars.
struct DailyLoadChart: View {
    let days: [TrainingLoad.Day]
    var selected: Date?

    var body: some View {
        Chart {
            ForEach(days) { day in
                if day.load > 0 {
                    BarMark(
                        x: .value("Day", day.date.startOfDay(in: .current), unit: .day),
                        y: .value("Load", day.load)
                    )
                    .foregroundStyle(Color.secondary)
                }
            }
            if let selected {
                SelectionRule(date: selected)
            }
        }
        .dayChartStyle(count: days.count)
    }
}

/// How far back the training load detail looks.
private enum LoadRange: Int, CaseIterable, Identifiable {
    case sixWeeks = 42
    case threeMonths = 90

    var id: Self { self }

    var label: String {
        switch self {
        case .sixWeeks: String(localized: "6W")
        case .threeMonths: String(localized: "3M")
        }
    }
}

/// Fitness, fatigue and form in depth, with what the form zones mean.
struct TrainingLoadDetailView: View {
    let days: [TrainingLoad.Day]
    @State private var range = LoadRange.threeMonths
    @State private var selectedDate: Date?

    private var shown: [TrainingLoad.Day] { Array(days.suffix(range.rawValue)) }

    private var selectedDay: TrainingLoad.Day? {
        guard let selectedDate else { return shown.last }
        return shown.first {
            Calendar.current.isDate($0.date.startOfDay(in: .current), inSameDayAs: selectedDate)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Picker("Range", selection: $range) {
                    ForEach(LoadRange.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                header
                charts
                zones
                about
            }
            .padding()
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Training Load")
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.selection, trigger: selectedDay?.date)
        .onChange(of: range) { selectedDate = nil }
    }

    @ViewBuilder private var header: some View {
        if let day = selectedDay {
            VStack(alignment: .leading, spacing: 8) {
                Text(Self.caption(of: day))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                LoadSummary(day: day)
            }
            .animation(.snappy, value: day)
        }
    }

    /// `Tuesday 28 October · load 142`.
    private static func caption(of day: TrainingLoad.Day) -> String {
        let date = day.date.startOfDay(in: .current)
            .formatted(.dateTime.weekday(.wide).day().month(.wide))
        return String(localized: "\(date) · load \(Int(day.load.rounded()))")
    }

    private var charts: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Fitness and Fatigue").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            LoadChart(days: shown, selected: selectedDay?.date.startOfDay(in: .current))
                .chartXSelection(value: $selectedDate)
                .chartHeight(200)
            Text("Form").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            FormChart(days: shown, selected: selectedDay?.date.startOfDay(in: .current))
                .chartXSelection(value: $selectedDate)
                .chartHeight(120)
            Text("Daily Load").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            DailyLoadChart(days: shown, selected: selectedDay?.date.startOfDay(in: .current))
                .chartXSelection(value: $selectedDate)
                .chartHeight(80)
        }
        .cardStyle()
    }

    private var zones: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Form Zones")
                .font(.headline)
                .padding(.bottom, 8)
            VStack(spacing: 0) {
                ForEach(FormZone.allCases.reversed(), id: \.self) { zone in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Image(systemName: zone.symbol)
                            .foregroundStyle(zone.color)
                            .frame(width: 22)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(zone.title).font(.body.weight(.semibold))
                            Text(zone.explanation).font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Text(Self.bandLabel(zone))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 10)
                    .accessibilityElement(children: .combine)
                    if zone != .overreaching {
                        Divider()
                    }
                }
            }
            .padding(.horizontal, 16)
            .background(
                Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
        }
    }

    /// `−30 to −10 %`, open-ended for the outer zones.
    private static func bandLabel(_ zone: FormZone) -> String {
        let low = Int((zone.band.lowerBound * 100).rounded())
        let high = Int((zone.band.upperBound * 100).rounded())
        return switch zone {
        case .detraining: "> \(low)%"
        case .overreaching: "< \(high)%"
        default: "\(low) to \(high)%"
        }
    }

    private var about: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("How It Works", systemImage: "info.circle")
                .font(.headline)
            Text(
                """
                Every activity's training load is Garmin's estimate of the oxygen debt (EPOC) \
                it caused. Fitness is your load averaged over about six weeks, fatigue over \
                about one week. Form is fitness minus fatigue: it drops while you train more \
                than you are used to and rises as you rest. Its zones are shares of fitness, \
                so they fit every athlete.
                """
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(.top, 8)
    }
}
