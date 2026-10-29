import Charts
import GCPAPISync
import SwiftUI
import UIKit

/// The overview in depth: every metric scaled to 0...1 over a longer range, with each
/// metric's real values for the day being scrubbed.
struct OverviewDetailView: View {
    let model: HealthModel
    @State private var range = HistoryRange.month
    @State private var selectedDate: Date?
    @State private var hidden: Set<OverviewMetric> = []
    @AppStorage("overview.higherIsBetter") private var higherIsBetter = false
    @AppStorage("overview.averagesWeeks") private var averagesWeeks = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Picker("Range", selection: $range) {
                    ForEach(HistoryRange.allCases) { range in
                        Text(range.label).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                content
            }
            .padding()
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Trends")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: loadedDays) {
            selectedDate = nil
            await model.loadHistory(days: loadedDays)
        }
        .sensoryFeedback(.selection, trigger: selectedDay?.date)
    }

    private var history: HealthHistory? { model.histories[loadedDays] }

    /// The days each value averages: a week for the longer ranges, unless turned off.
    private var averaging: Int {
        averagesWeeks && range != .week ? 7 : 1
    }

    /// The range plus the days that lead into the first average.
    private var loadedDays: Int {
        range.days + averaging - 1
    }

    private var shown: [OverviewMetric] {
        OverviewMetric.allCases.filter { !hidden.contains($0) }
    }

    private var selectedDay: DayHealth? {
        guard let selectedDate else { return nil }
        return history?.days.first { Calendar.current.isDate($0.start, inSameDayAs: selectedDate) }
    }

    @ViewBuilder private var content: some View {
        if let history {
            chart(history)
            values(history)
            about
        } else if let problem = model.historyProblems[loadedDays] {
            ContentUnavailableView {
                Label(problem.title, systemImage: problem.symbol)
            } description: {
                Text(problem.message)
            } actions: {
                Button("Try Again") {
                    Task { await model.loadHistory(days: loadedDays) }
                }
                .buttonStyle(.glassProminent)
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 320)
        }
    }

    private func chart(_ history: HealthHistory) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            OverviewChart(
                days: history.days, metrics: shown, averaging: averaging,
                higherIsBetter: higherIsBetter, selected: selectedDay?.start
            )
            .chartXSelection(value: $selectedDate)
            .frame(height: 280)
            .animation(.snappy, value: shown)
            .animation(.snappy, value: higherIsBetter)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], spacing: 8) {
                ForEach(OverviewMetric.allCases) { metric in
                    MetricToggle(metric: metric, isOn: !hidden.contains(metric)) {
                        toggle(metric)
                    }
                }
            }
            if range != .week {
                Toggle(isOn: $averagesWeeks) {
                    ToggleLabel(
                        title: "7-Day Average",
                        detail: "Each day shows the mean of the week ending on it")
                }
            }
            Toggle(isOn: $higherIsBetter) {
                ToggleLabel(
                    title: "Higher Is Better",
                    detail: "Flips resting heart rate and stress, so up always means a better day")
            }
        }
        .padding(20)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 26))
    }

    /// Hides or shows `metric`, keeping at least one line on the chart.
    private func toggle(_ metric: OverviewMetric) {
        if hidden.contains(metric) {
            hidden.remove(metric)
        } else if shown.count > 1 {
            hidden.insert(metric)
        }
    }

    /// Each metric's value on the selected day, or its range over the days shown.
    private func values(_ history: HealthHistory) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if let selectedDay {
                    let date = selectedDay.start.formatted(
                        .dateTime.weekday(.wide).day().month(.wide))
                    Text(averaging > 1 ? String(localized: "\(date) · 7-day average") : date)
                } else {
                    Text("Ranges · \(range.caption)")
                }
            }
            .font(.headline)
            .contentTransition(.numericText())
            .padding(.bottom, 8)
            VStack(spacing: 0) {
                ForEach(OverviewMetric.allCases) { metric in
                    ValueRow(
                        metric: metric,
                        points: metric.scaled(
                            history.days, averaging: averaging, higherIsBetter: higherIsBetter),
                        day: selectedDay)
                    if metric != OverviewMetric.allCases.last {
                        Divider()
                    }
                }
            }
            .padding(.horizontal, 16)
            .background(
                Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
        }
        .animation(.snappy, value: selectedDay?.date)
    }

    private var about: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("About Trends", systemImage: "info.circle")
                .font(.headline)
            Text(
                """
                HRV, resting heart rate, sleep score, stress and VO2max have different units, \
                so each line is scaled to its own range over the days shown: 0 is the lowest \
                value and 1 the highest. The chart shows how the metrics move together, not \
                how large they are. Over 30 and 90 days, a 7-day average smooths out single \
                days. VO2max is estimated from your runs.
                """
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(.top, 8)
    }
}

/// A setting's name with a line about what it does.
private struct ToggleLabel: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

/// A legend entry that hides or shows its metric.
private struct MetricToggle: View {
    let metric: OverviewMetric
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            OverviewLegendLabel(metric: metric)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .opacity(isOn ? 1 : 0.4)
                .background(
                    isOn ? metric.color.opacity(0.14) : Color.clear, in: .capsule
                )
                .overlay {
                    Capsule().strokeBorder(metric.color.opacity(isOn ? 0 : 0.4))
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(metric.title)
        .accessibilityValue(isOn ? Text("Shown") : Text("Hidden"))
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// A metric's value and its place in the range, or the range itself without a day.
private struct ValueRow: View {
    let metric: OverviewMetric
    /// The metric's values over the range shown.
    let points: [ScaledValue]
    let day: DayHealth?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            OverviewLegendLabel(metric: metric)
                .font(.body)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(primary)
                    .font(.body.monospacedDigit().weight(.semibold))
                    .contentTransition(.numericText())
                if let secondary {
                    Text(secondary)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }

    private var point: ScaledValue? {
        day.flatMap { day in points.first { $0.date == day.date } }
    }

    private var primary: String {
        if day != nil {
            return metric.formatted(point?.value)
        }
        let values = points.map(\.value)
        guard let low = values.min(), let high = values.max() else { return "–" }
        return "\(metric.formatted(low)) – \(metric.formatted(high))"
    }

    /// Where the selected day lies between 0 and 1.
    private var secondary: String? {
        point.map { $0.scaled.formatted(.number.precision(.fractionLength(2))) }
    }
}

#Preview {
    NavigationStack {
        OverviewDetailView(model: HealthModel { end, days in .sample(endingOn: end, days: days) })
    }
}
