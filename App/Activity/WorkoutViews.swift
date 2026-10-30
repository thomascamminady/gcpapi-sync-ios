import GCPAPISync
import SwiftUI

/// An activity in a list: its sport, name, time, and headline numbers.
struct WorkoutRow: View {
    let workout: Workout
    @Environment(\.isDense) private var isDense

    var body: some View {
        HStack(spacing: isDense ? 8 : 12) {
            SportIcon(sport: workout.sport, size: isDense ? 28 : 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(workout.name)
                    .font((isDense ? Font.subheadline : .body).weight(.semibold))
                    .lineLimit(1)
                Text(when)
                    .font(isDense ? .caption : .subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(primary)
                    .font(.body.monospacedDigit().weight(.semibold))
                Text(secondary)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    /// `Thu, 29 Oct · 07:12`.
    private var when: String {
        let start = workout.start ?? workout.date.startOfDay(in: .current)
        let day = start.formatted(.dateTime.weekday(.abbreviated).day().month(.twoDigits))
        return "\(day) · \(start.formatted(.dateTime.hour().minute()))"
    }

    /// The distance, or the duration for activities without one.
    private var primary: String {
        workout.distance.map(Format.distance) ?? Format.clock(seconds: workout.duration)
    }

    private var secondary: String {
        if workout.distance != nil {
            let pace = workout.averageSpeed.map {
                Format.pace(metresPerSecond: $0, sport: workout.sport)
            }
            return [Format.clock(seconds: workout.duration), pace].compactMap(\.self)
                .joined(separator: " · ")
        }
        return workout.averageHeartRate.map { "\(Int($0.rounded())) bpm" }
            ?? workout.sport.title
    }
}

/// A sport's symbol on a disc of its color.
struct SportIcon: View {
    let sport: Sport
    var size: CGFloat = 40

    var body: some View {
        Image(systemName: sport.symbol)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(sport.color)
            .frame(width: size, height: size)
            .background(sport.color.opacity(0.15), in: .circle)
            .accessibilityLabel(sport.title)
    }
}

/// Every activity of the last 90 days by week, searchable and filtered by sport.
struct ActivityListView: View {
    let data: TrainingData
    @Environment(\.isDense) private var isDense
    @State private var query = ""
    @State private var sport: Sport?

    private var filtered: [Workout] {
        data.workouts.filter { workout in
            (sport.map { $0 == workout.sport } ?? true)
                && (query.isEmpty || workout.name.localizedStandardContains(query))
        }
    }

    private var weeks: [(start: GarminDate, workouts: [Workout])] {
        Dictionary(grouping: filtered) { TrainingWeek.weekStart(of: $0.date, calendar: .app) }
            .map { (start: $0.key, workouts: $0.value) }
            .sorted { $0.start > $1.start }
    }

    /// The activities of the last seven days, today included.
    private var recent: [Workout] {
        let first = GarminDate.today().adding(days: -6)
        return data.workouts.filter { $0.date >= first }
    }

    var body: some View {
        List {
            if query.isEmpty, sport == nil {
                Section("Last 7 Days") {
                    RecentSummary(workouts: recent)
                }
            }
            ForEach(weeks, id: \.start) { week in
                Section {
                    ForEach(week.workouts) { workout in
                        NavigationLink(value: ActivityRoute.workout(workout)) {
                            WorkoutRow(workout: workout)
                        }
                        .accessibilityIdentifier("workout.\(workout.sport.rawValue)")
                    }
                } header: {
                    WeekHeader(start: week.start, workouts: week.workouts)
                }
            }
        }
        .overlay {
            if filtered.isEmpty {
                if query.isEmpty {
                    ContentUnavailableView(
                        "No Activities", systemImage: "figure.run",
                        description: Text("Nothing recorded in the last 90 days."))
                } else {
                    ContentUnavailableView.search(text: query)
                }
            }
        }
        .environment(\.defaultMinListRowHeight, isDense ? 34 : 44)
        .searchable(text: $query, prompt: "Activity name")
        .navigationTitle("Activities")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Sport", selection: $sport) {
                        Label("All Sports", systemImage: "square.grid.2x2").tag(Sport?.none)
                        ForEach(
                            Sport.allCases.filter { sport in
                                data.workouts.contains { $0.sport == sport }
                            }
                        ) { sport in
                            Label(sport.title, systemImage: sport.symbol).tag(Sport?.some(sport))
                        }
                    }
                } label: {
                    Label(
                        "Sport",
                        systemImage: sport == nil
                            ? "line.3.horizontal.decrease.circle"
                            : "line.3.horizontal.decrease.circle.fill")
                }
            }
        }
    }
}

/// A week's dates and totals above its activities.
private struct WeekHeader: View {
    let start: GarminDate
    let workouts: [Workout]

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text("\(Format.hours(seconds: totalSeconds)) · \(workouts.count)")
                .monospacedDigit()
        }
    }

    private var totalSeconds: Double {
        workouts.reduce(0) { $0 + $1.duration }
    }

    private var title: String {
        let current = TrainingWeek.weekStart(of: .today(), calendar: .app)
        if start == current {
            return String(localized: "This Week")
        }
        if start == current.adding(days: -7) {
            return String(localized: "Last Week")
        }
        let first = start.startOfDay(in: .current)
        let last = start.adding(days: 6).startOfDay(in: .current)
        return (first..<last).formatted(.interval.day().month(.abbreviated))
    }
}
