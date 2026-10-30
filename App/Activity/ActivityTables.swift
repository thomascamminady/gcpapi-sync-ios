import SwiftUI

/// Pace (or speed), heart rate and climb of every kilometre or mile.
struct SplitsCard: View {
    let splits: [ActivityTrack.Split]
    let sport: Sport

    var body: some View {
        let fastest = splits.map(\.speed).max() ?? 1
        VStack(alignment: .leading, spacing: 10) {
            CardHeader(
                title: Format.usesMiles ? "Splits per Mile" : "Splits per Kilometre",
                symbol: "flag.2.crossed.fill", tint: sport.color)
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    Text(Format.usesMiles ? "mi" : "km")
                    Text(TrackMeasure.usesPace(sport) ? "Pace" : "Speed")
                        .gridCellColumns(2)
                    Text("HR").gridColumnAlignment(.trailing)
                    Text("Climb").gridColumnAlignment(.trailing)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                ForEach(splits) { split in
                    GridRow {
                        Text(label(split))
                            .foregroundStyle(.secondary)
                        Text(Format.pace(metresPerSecond: split.speed, sport: sport))
                        Capsule()
                            .fill(sport.color.opacity(split.speed == fastest ? 1 : 0.45))
                            .frame(width: max(4, 56 * split.speed / fastest), height: 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(split.heartRate.map { "\(Int($0.rounded()))" } ?? "–")
                        Text("+\(Int(split.ascent.rounded()))")
                            .foregroundStyle(.secondary)
                    }
                    .font(.subheadline.monospacedDigit())
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .cardStyle()
    }

    /// The split's number, or its length when it is the shorter last one.
    private func label(_ split: ActivityTrack.Split) -> String {
        let unit = Format.usesMiles ? 1609.344 : 1000
        guard split.distance < unit * 0.98 else { return "\(split.number)" }
        return (split.distance / unit).formatted(.number.precision(.fractionLength(2)))
    }
}

/// The laps recorded by the watch.
struct LapsCard: View {
    let laps: [FITActivity.Lap]
    let sport: Sport

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardHeader(title: "Laps", symbol: "stopwatch.fill", tint: sport.color)
            ForEach(Array(laps.enumerated()), id: \.offset) { index, lap in
                HStack(alignment: .firstTextBaseline) {
                    Text("\(index + 1)")
                        .frame(width: 26, alignment: .leading)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(lap.distance.map(Format.distance) ?? "–")
                        Text((lap.moving ?? lap.elapsed).map(Format.clock) ?? "–")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let speed = lap.averageSpeed, speed > 0 {
                        Text(Format.pace(metresPerSecond: speed, sport: sport))
                    }
                    Text(lap.averageHeartRate.map { "\($0) bpm" } ?? "")
                        .frame(width: 72, alignment: .trailing)
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline.monospacedDigit())
                .accessibilityElement(children: .combine)
                if index < laps.count - 1 {
                    Divider()
                }
            }
        }
        .cardStyle()
    }
}

/// Strength training sets: exercise, repetitions and weight.
struct SetsCard: View {
    let sets: [FITActivity.ExerciseSet]

    /// The active sets with something to show.
    static func logged(_ sets: [FITActivity.ExerciseSet]) -> [FITActivity.ExerciseSet] {
        sets.filter { $0.isActive && ($0.repetitions != nil || $0.category != nil) }
    }

    var body: some View {
        let logged = Self.logged(sets)
        VStack(alignment: .leading, spacing: 10) {
            CardHeader(title: "Sets", symbol: "dumbbell.fill", tint: Sport.strength.color)
            ForEach(Array(logged.enumerated()), id: \.offset) { index, set in
                HStack(alignment: .firstTextBaseline) {
                    Text(
                        ExerciseCategory.name(set.category) ?? String(localized: "Set \(index + 1)")
                    )
                    .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(Self.detail(set))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .cardStyle()
    }

    /// `8 × 80 kg · 0:45`.
    static func detail(_ set: FITActivity.ExerciseSet) -> String {
        let weight = set.weight.map {
            Measurement(value: $0, unit: UnitMass.kilograms)
                .converted(to: Format.usesMiles ? .pounds : .kilograms)
                .formatted(
                    .measurement(
                        width: .abbreviated, usage: .asProvided,
                        numberFormatStyle: .number.precision(.fractionLength(0...1))))
        }
        let load = [set.repetitions.map { "\($0)" }, weight].compactMap(\.self).joined(
            separator: " × ")
        return [load.isEmpty ? nil : load, set.duration.map(Format.clock)].compactMap(\.self)
            .joined(separator: " · ")
    }
}
