import GCPAPISync
import SwiftUI

/// A week of activities as a table, newest first, one row each with every figure Garmin has,
/// and below it the week's totals of each sport.
struct ActivityLogTable: View {
    let workouts: [Workout]
    /// The days to show, newest first: a dash for each without an activity.
    let days: [GarminDate]
    /// Whether to leave out the columns that matter least: ascent, energy and training effect.
    var isNarrow = false
    @ScaledMetric(relativeTo: .subheadline) private var unit: CGFloat = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            activityRows
            if !workouts.isEmpty {
                Divider()
                ForEach(Array(sportTotals.enumerated()), id: \.offset) { index, item in
                    DeskRow(index: index) {
                        totals(item.totals, of: item.sport)
                    }
                }
            }
        }
        .font(DeskStyle.font)
        .monospacedDigit()
    }

    private var activityRows: some View {
        ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
            switch row {
            case .activity(let workout, let showsDay):
                NavigationLink(value: ActivityRoute.workout(workout)) {
                    DeskRow(index: index) {
                        self.row(workout, showsDay: showsDay)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("log.\(workout.sport.rawValue)")
            case .rest(let date):
                DeskRow(index: index) {
                    Text(Self.day(date)).cell(unit * 11.5, alignment: .leading)
                    Text(verbatim: "").cell(unit * 2.5)
                    Text(verbatim: "–")
                        .foregroundStyle(.tertiary)
                        .flexibleCell()
                        .accessibilityLabel(Text("No activities."))
                }
            }
        }
    }

    /// A row of the table: an activity, or a day without one.
    enum Row {
        case activity(Workout, showsDay: Bool)
        case rest(GarminDate)
    }

    /// Each day's activities, newest first, with the day named on its first; a dash for a day
    /// without any.
    var rows: [Row] {
        let byDay = Dictionary(grouping: workouts, by: \.date)
        return days.flatMap { day -> [Row] in
            let activities = byDay[day] ?? []
            guard !activities.isEmpty else { return [.rest(day)] }
            return activities.enumerated().map { .activity($1, showsDay: $0 == 0) }
        }
    }

    private var sportTotals: [(sport: Sport, totals: ActivityTotals)] {
        ActivityTotals.bySport(workouts)
    }

    private var header: some View {
        DeskHeader {
            Text("Day").cell(unit * 11.5, alignment: .leading)
            Text(verbatim: "").cell(unit * 2.5)
            Text("Activity").flexibleCell()
            Text("Distance").cell(unit * 8.5)
            Text("Time").cell(unit * 8.5)
            Text("Pace").cell(unit * 8.5)
            if !isNarrow {
                Text("Ascent").cell(unit * 7.5)
                Text("Energy").cell(unit * 10)
            }
            Text("Avg HR").cell(unit * 8.5)
            Text("Load").cell(unit * 5.5)
            if !isNarrow {
                Text("TE").cell(unit * 4)
                    .help(Text("Aerobic training effect"))
            }
        }
    }

    @ViewBuilder
    private func row(_ workout: Workout, showsDay: Bool) -> some View {
        Text(showsDay ? Self.day(workout.date) : "")
            .cell(unit * 11.5, alignment: .leading)
        Image(systemName: workout.sport.symbol)
            .foregroundStyle(workout.sport.color)
            .cell(unit * 2.5, alignment: .center)
            .accessibilityLabel(workout.sport.title)
        Text(workout.name).flexibleCell()
        Text(workout.distance.map(Format.distance) ?? "").cell(unit * 8.5)
        Text(Format.clock(seconds: workout.duration)).cell(unit * 8.5)
        Text(
            workout.averageSpeed.map { Format.pace(metresPerSecond: $0, sport: workout.sport) }
                ?? ""
        )
        .cell(unit * 8.5)
        if !isNarrow {
            Text(
                workout.elevationGain.flatMap { $0 > 0 ? Format.elevation(metres: $0) : nil } ?? ""
            )
            .cell(unit * 7.5)
            Text(workout.calories.map(Format.energy) ?? "").cell(unit * 10)
        }
        Text(workout.averageHeartRate.map { Format.heartRate($0) } ?? "").cell(unit * 8.5)
        Text(workout.trainingLoad.map { Int($0.rounded()).formatted() } ?? "")
            .foregroundStyle(Self.effectColor(workout.aerobicEffect))
            .cell(unit * 5.5)
        if !isNarrow {
            Text(
                workout.aerobicEffect.map { $0.formatted(.number.precision(.fractionLength(1))) }
                    ?? ""
            )
            .foregroundStyle(Self.effectColor(workout.aerobicEffect))
            .cell(unit * 4)
        }
    }

    @ViewBuilder
    private func totals(_ totals: ActivityTotals, of sport: Sport) -> some View {
        Text(verbatim: "").cell(unit * 11.5)
        Image(systemName: sport.symbol)
            .foregroundStyle(sport.color)
            .cell(unit * 2.5, alignment: .center)
            .accessibilityHidden(true)
        Text("\(totals.activityCount)× \(sport.title)").flexibleCell()
        Text(totals.distance > 0 ? Format.distance(metres: totals.distance) : "").cell(unit * 8.5)
        Text(Format.clock(seconds: totals.duration)).cell(unit * 8.5)
        Text(totals.averageSpeed.map { Format.pace(metresPerSecond: $0, sport: sport) } ?? "")
            .cell(unit * 8.5)
        if !isNarrow {
            Text(totals.ascent > 0 ? Format.elevation(metres: totals.ascent) : "").cell(unit * 7.5)
            Text(totals.calories > 0 ? Format.energy(totals.calories) : "").cell(unit * 10)
        }
        Text(totals.averageHeartRate.map { Format.heartRate($0) } ?? "").cell(unit * 8.5)
        Text(totals.load > 0 ? Int(totals.load.rounded()).formatted() : "").cell(unit * 5.5)
        if !isNarrow {
            Text(verbatim: "").cell(unit * 4)
        }
    }

    /// `Fri 30.10.` or `Fri, 10/30`.
    static func day(_ date: GarminDate) -> String {
        date.startOfDay(in: .current).formatted(
            .dateTime.weekday(.abbreviated).day().month(.twoDigits))
    }

    /// Hard sessions stand out: the color of the zone their aerobic training effect reaches.
    static func effectColor(_ effect: Double?) -> Color {
        guard let effect, effect >= 3 else { return .secondary }
        return ColorRole.zone(min(Int(effect), 5) - 1).color
    }
}

/// The totals of each of the last months for one sport or all: activities, distance, time, pace
/// and the rest, with a bar of each month's volume.
struct MonthlyStatisticsTable: View {
    let months: [ActivityTotals.Month]
    /// The sport the months are of, or `nil` for all.
    let sport: Sport?
    var isNarrow = false
    /// Whether figures are shaded by the color map: sums from zero to the largest month,
    /// averages from the lowest to the highest.
    var isShaded = false
    @ScaledMetric(relativeTo: .subheadline) private var unit: CGFloat = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DeskHeader {
                Text("Month").cell(unit * 11.5, alignment: .leading)
                Text(verbatim: "").cell(unit * 4)
                Text("Distance").cell(unit * 9.5)
                Text(verbatim: "").cell(unit * 5.5)
                Text("Time").cell(unit * 10.5)
                if hasPace {
                    Text("Pace").cell(unit * 8.5)
                }
                if !isNarrow {
                    Text("Ascent").cell(unit * 8)
                    Text("Energy").cell(unit * 10.5)
                }
                Text("Avg HR").cell(unit * 8.5)
                Text("Load").cell(unit * 6.5)
                Text("Volume").flexibleCell()
            }
            Divider()
            ForEach(Array(months.enumerated()), id: \.element.id) { index, month in
                DeskRow(index: index) {
                    row(month, before: months.indices.contains(index + 1) ? months[index + 1] : nil)
                }
            }
            if isShaded {
                shadingLegend
            }
        }
        .font(DeskStyle.font)
        .monospacedDigit()
    }

    /// What the shades mean.
    private var shadingLegend: some View {
        HStack(spacing: 8) {
            Capsule()
                .fill(Preferences.shared.valueGradient)
                .frame(width: 80, height: 6)
                .accessibilityHidden(true)
            Text(
                """
                Distance, time and load from zero to the largest month; pace and heart \
                rate from the lowest to the highest.
                """)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.top, 8)
        .padding(.horizontal, 8)
    }

    /// The months that have activities, which shading compares.
    private var active: [ActivityTotals] {
        months.map(\.totals).filter { $0.activityCount > 0 }
    }

    /// A figure, on its color when shaded.
    private func figure(_ text: String, _ fraction: Double?, width: CGFloat) -> some View {
        let shade = isShaded ? fraction : nil
        return Text(text)
            .foregroundStyle(shade.map { Preferences.shared.valueTextColor($0) } ?? .primary)
            .cell(width)
            .background {
                // Into the space between the columns, so that the figure keeps its width.
                if let shade {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Preferences.shared.valueColor(shade))
                        .padding(.horizontal, -4)
                        .padding(.vertical, -3)
                }
            }
    }

    /// Pace or speed only means something for a single sport that has a distance.
    private var hasPace: Bool {
        sport.map { $0 != .strength && $0 != .other } ?? false
    }

    /// Distance for sports that have one, time for the rest and for all sports together.
    private func volume(_ totals: ActivityTotals) -> Double {
        hasPace ? totals.distance : totals.duration
    }

    @ViewBuilder
    private func row(_ month: ActivityTotals.Month, before: ActivityTotals.Month?) -> some View {
        let totals = month.totals
        let largest = months.map { volume($0.totals) }.max() ?? 0
        Text(Self.title(month.first)).cell(unit * 11.5, alignment: .leading)
        Text(totals.activityCount > 0 ? String(localized: "\(totals.activityCount)×") : "")
            .foregroundStyle(.secondary)
            .cell(unit * 4)
        figure(
            totals.distance > 0 ? Format.distance(metres: totals.distance) : "",
            ValueScale.fromZero(totals.distance, among: active.map(\.distance)), width: unit * 9.5)
        change(of: totals.distance, from: before?.totals.distance).cell(unit * 5.5)
        figure(
            totals.duration > 0 ? Format.hours(seconds: totals.duration) : "",
            ValueScale.fromZero(totals.duration, among: active.map(\.duration)), width: unit * 10.5)
        if hasPace, let sport {
            figure(
                totals.averageSpeed.map { Format.pace(metresPerSecond: $0, sport: sport) } ?? "",
                ValueScale.between(totals.averageSpeed, among: active.compactMap(\.averageSpeed)),
                width: unit * 8.5)
        }
        if !isNarrow {
            Text(totals.ascent > 0 ? Format.elevation(metres: totals.ascent) : "").cell(unit * 8)
            Text(totals.calories > 0 ? Format.energy(totals.calories) : "").cell(unit * 10.5)
        }
        figure(
            totals.averageHeartRate.map { Format.heartRate($0) } ?? "",
            ValueScale.between(
                totals.averageHeartRate, among: active.compactMap(\.averageHeartRate)),
            width: unit * 8.5)
        figure(
            totals.load > 0 ? Int(totals.load.rounded()).formatted() : "",
            ValueScale.fromZero(totals.load, among: active.map(\.load)), width: unit * 6.5)
        MeterBar(
            fraction: largest > 0 ? volume(totals) / largest : 0,
            color: sport?.color ?? ColorRole.accent.color
        )
        .flexibleCell()
    }

    /// The change from the month before, in percent; nothing without one.
    private func change(of value: Double, from before: Double?) -> some View {
        let percent = before.flatMap { $0 > 0 ? (value / $0 - 1) : nil }
        return Text(
            percent.map {
                $0.formatted(.percent.precision(.fractionLength(0)).sign(strategy: .always()))
            } ?? ""
        )
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    /// `October`, or `October 2025` for a month of another year.
    static func title(_ first: GarminDate) -> String {
        let date = first.startOfDay(in: .current)
        let thisYear = Calendar.current.component(.year, from: .now) == first.year
        return date.formatted(thisYear ? .dateTime.month(.wide) : .dateTime.month(.wide).year())
    }
}

extension Format {
    /// `157 kcal`.
    nonisolated static func energy(_ kilocalories: Double) -> String {
        Measurement(value: kilocalories, unit: UnitEnergy.kilocalories).formatted(
            .measurement(
                width: .abbreviated, usage: .asProvided,
                numberFormatStyle: .number.precision(.fractionLength(0))))
    }

    /// `142 bpm`.
    nonisolated static func heartRate(_ beatsPerMinute: Double) -> String {
        String(localized: "\(Int(beatsPerMinute.rounded())) bpm")
    }
}
