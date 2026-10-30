import GCPAPISync
import SwiftUI
import UIKit

/// Activities by month: a calendar with a dot per activity in its sport's color, and the
/// chosen day's activities below.
struct ActivityCalendarView: View {
    let model: TrainingModel
    @State private var month = CalendarMonth.first(of: .today())
    @State private var selected: GarminDate? = .today()
    @Environment(\.isDense) private var isDense

    private var workouts: [Workout]? { model.workouts(inMonthStarting: month) }

    var body: some View {
        List {
            Section {
                MonthHeader(month: $month)
                MonthGrid(month: month, workouts: workouts ?? [], selected: $selected)
                if let workouts {
                    MonthSummary(workouts: workouts)
                } else if let problem = model.archiveProblems[month] {
                    Label(problem.message, systemImage: problem.symbol)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                }
            }
            daySection
        }
        .task(id: month) { await model.loadMonth(startingOn: month) }
        .onChange(of: month) { selected = nil }
    }
}

extension ActivityCalendarView {
    /// The chosen day's activities.
    @ViewBuilder var daySection: some View {
        if let selected, let workouts {
            let day = workouts.filter { $0.date == selected }
            Section(
                selected.startOfDay(in: .current).formatted(
                    .dateTime.weekday(.wide).day().month(.wide))
            ) {
                if day.isEmpty {
                    Text("No activities.")
                        .foregroundStyle(.secondary)
                }
                ForEach(day) { workout in
                    NavigationLink(value: ActivityRoute.workout(workout)) {
                        WorkoutRow(workout: workout)
                    }
                }
            }
        }
    }
}

/// The month's name between buttons to the months before and after.
private struct MonthHeader: View {
    @Binding var month: GarminDate

    var body: some View {
        HStack {
            Button("Previous Month", systemImage: "chevron.left") {
                month = CalendarMonth.adding(months: -1, to: month)
            }
            Spacer()
            Text(month.startOfDay(in: .current), format: .dateTime.month(.wide).year())
                .font(.headline)
                .contentTransition(.numericText())
            Spacer()
            Button("Next Month", systemImage: "chevron.right") {
                month = CalendarMonth.adding(months: 1, to: month)
            }
            .disabled(month >= CalendarMonth.first(of: .today()))
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .animation(.snappy, value: month)
    }
}

/// The days of a month in weeks, each with dots for its activities.
private struct MonthGrid: View {
    let month: GarminDate
    let workouts: [Workout]
    @Binding var selected: GarminDate?

    var body: some View {
        let calendar = Calendar.app
        let byDay = Dictionary(grouping: workouts, by: \.date)
        let blanks = CalendarMonth.leadingBlanks(of: month, calendar: calendar)
        let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(
                Array(CalendarMonth.weekdaySymbols(calendar: calendar).enumerated()), id: \.offset
            ) {
                Text($0.element)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            ForEach(0..<blanks, id: \.self) { _ in
                Color.clear.frame(height: 1)
            }
            ForEach(CalendarMonth.days(of: month), id: \.self) { day in
                DayCell(
                    day: day, workouts: byDay[day] ?? [], isSelected: day == selected,
                    isToday: day == .today()
                ) {
                    selected = day
                }
            }
        }
        .sensoryFeedback(.selection, trigger: selected)
    }
}

/// A day's number and a dot per activity, up to three.
private struct DayCell: View {
    let day: GarminDate
    let workouts: [Workout]
    let isSelected: Bool
    let isToday: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Text("\(day.day)")
                    .font(.callout.weight(isToday ? .bold : .regular).monospacedDigit())
                    .foregroundStyle(
                        isSelected ? Color.white : (isToday ? Color.accentColor : .primary)
                    )
                    .frame(width: 32, height: 32)
                    .background(isSelected ? Color.accentColor : .clear, in: .circle)
                HStack(spacing: 2) {
                    ForEach(workouts.prefix(3)) { workout in
                        Circle().fill(workout.sport.color).frame(width: 5, height: 5)
                    }
                }
                .frame(height: 5)
            }
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.startOfDay(in: .current).formatted(date: .complete, time: .omitted))
        .accessibilityValue(Format.activities(workouts.count))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The month's activities, time and distance.
private struct MonthSummary: View {
    let workouts: [Workout]

    var body: some View {
        let distance = workouts.compactMap(\.distance).reduce(0, +)
        let parts = [
            Format.activities(workouts.count),
            Format.hours(seconds: workouts.reduce(0) { $0 + $1.duration }),
            distance > 0 ? Format.distance(metres: distance) : nil,
        ]
        Text(parts.compactMap(\.self).joined(separator: " · "))
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
    }
}
