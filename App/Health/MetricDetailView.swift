import Charts
import GCPAPISync
import SwiftUI
import UIKit

/// How far back a detail screen looks.
enum HistoryRange: Int, CaseIterable, Identifiable {
    case week = 7
    case month = 30
    case quarter = 90

    var id: Self { self }
    var days: Int { rawValue }

    var label: String {
        switch self {
        case .week: String(localized: "7D")
        case .month: String(localized: "30D")
        case .quarter: String(localized: "90D")
        }
    }

    var caption: String {
        String(localized: "Last \(days) days")
    }
}

/// One metric in depth: a longer range, a chart to scrub through, every day's value.
struct MetricDetailView: View {
    let metric: Metric
    let model: HealthModel
    @State private var range = HistoryRange.week
    @State private var selectedDate: Date?

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
        .navigationTitle(metric.title)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: range) {
            selectedDate = nil
            await model.loadHistory(days: range.days)
        }
        .sensoryFeedback(.selection, trigger: selectedDay?.date)
    }

    private var history: HealthHistory? { model.histories[range.days] }

    private var selectedDay: DayHealth? {
        guard let selectedDate else { return nil }
        return history?.days.first { Calendar.current.isDate($0.start, inSameDayAs: selectedDate) }
    }

    @ViewBuilder private var content: some View {
        if let history {
            header(history)
            chart(history)
            dayList(history)
            about
        } else if let problem = model.historyProblems[range.days] {
            ContentUnavailableView {
                Label(problem.title, systemImage: problem.symbol)
            } description: {
                Text(problem.message)
            } actions: {
                Button("Try Again") {
                    Task { await model.loadHistory(days: range.days) }
                }
                .buttonStyle(.glassProminent)
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 320)
        }
    }

    private func header(_ history: HealthHistory) -> some View {
        let summary = selectedDay.map(metric.summary(of:)) ?? metric.summary(of: history)
        let caption = selectedDay.map {
            $0.start.formatted(.dateTime.weekday(.wide).day().month(.wide))
        }
        return VStack(alignment: .leading, spacing: 4) {
            Text(caption ?? range.caption)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(summary.value)
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                if let unit = summary.unit {
                    Text(unit)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }
            Text(summary.detail.isEmpty ? " " : summary.detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .animation(.snappy, value: summary)
        .accessibilityElement(children: .combine)
    }

    private func chart(_ history: HealthHistory) -> some View {
        MetricChart(metric: metric, days: history.days, selected: selectedDay?.start)
            .chartXSelection(value: $selectedDate)
            .frame(height: 260)
            .padding(20)
            .background(
                Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 26))
    }

    private func dayList(_ history: HealthHistory) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Days")
                .font(.headline)
                .padding(.bottom, 8)
            LazyVStack(spacing: 0) {
                ForEach(history.days.reversed()) { day in
                    DayRow(metric: metric, day: day)
                    if day.date != history.days.first?.date {
                        Divider()
                    }
                }
            }
            .padding(.horizontal, 16)
            .background(
                Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
        }
    }

    private var about: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("About \(metric.title)", systemImage: "info.circle")
                .font(.headline)
            Text(metric.explanation)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 8)
    }
}

/// A day and its value.
private struct DayRow: View {
    let metric: Metric
    let day: DayHealth

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(day.start, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(metric.value(of: day))
                        .font(.body.monospacedDigit().weight(.semibold))
                    if metric.hasValue(day), let unit = metric.unit {
                        Text(unit)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if let detail = metric.detail(of: day) {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    NavigationStack {
        MetricDetailView(
            metric: .sleep, model: HealthModel { end, days in .sample(endingOn: end, days: days) })
    }
}
