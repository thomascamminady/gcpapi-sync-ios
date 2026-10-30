import GCPAPISync
import SwiftUI

/// A week of activities as a table, newest first, one row each with every figure Garmin has,
/// and below it the week's totals of each sport.
struct ActivityLogTable: View {
    let workouts: [Workout]
    /// Whether to leave out the columns that matter least: ascent, energy and training effect.
    var isNarrow = false
    @ScaledMetric(relativeTo: .subheadline) private var unit: CGFloat = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if workouts.isEmpty {
                Text("No activities.")
                    .foregroundStyle(.secondary)
                    .padding(8)
            }
            ForEach(Array(workouts.enumerated()), id: \.element.id) { index, workout in
                NavigationLink(value: ActivityRoute.workout(workout)) {
                    DeskRow(index: index) {
                        row(
                            workout,
                            showsDay: index == 0 || workouts[index - 1].date != workout.date)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("log.\(workout.sport.rawValue)")
            }
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
    @ScaledMetric(relativeTo: .subheadline) private var unit: CGFloat = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DeskHeader {
                Text("Month").cell(unit * 11.5, alignment: .leading)
                Text(verbatim: "").cell(unit * 4)
                Text("Distance").cell(unit * 9.5)
                Text(verbatim: "").cell(unit * 5.5)
                Text("Time").cell(unit * 9)
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
        }
        .font(DeskStyle.font)
        .monospacedDigit()
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
        Text(totals.activityCount > 0 ? "\(totals.activityCount)×" : "").foregroundStyle(.secondary)
            .cell(unit * 4)
        Text(totals.distance > 0 ? Format.distance(metres: totals.distance) : "").cell(unit * 9.5)
        change(of: totals.distance, from: before?.totals.distance).cell(unit * 5.5)
        Text(totals.duration > 0 ? Format.hours(seconds: totals.duration) : "").cell(unit * 9)
        if hasPace, let sport {
            Text(totals.averageSpeed.map { Format.pace(metresPerSecond: $0, sport: sport) } ?? "")
                .cell(unit * 8.5)
        }
        if !isNarrow {
            Text(totals.ascent > 0 ? Format.elevation(metres: totals.ascent) : "").cell(unit * 8)
            Text(totals.calories > 0 ? Format.energy(totals.calories) : "").cell(unit * 10.5)
        }
        Text(totals.averageHeartRate.map { Format.heartRate($0) } ?? "").cell(unit * 8.5)
        Text(totals.load > 0 ? Int(totals.load.rounded()).formatted() : "").cell(unit * 6.5)
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
