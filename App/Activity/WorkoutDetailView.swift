import GCPAPISync
import SwiftUI
import UIKit

/// One activity: its route, its recording over time, splits and laps, its numbers, Garmin's
/// training effect, and time in zones.
struct WorkoutDetailView: View {
    let workout: Workout
    let zones: HeartRateZoneSet?
    let model: TrainingModel
    /// The scrubbed moment, in seconds of timer time, shared by the charts and the map.
    @State private var selection: Double?
    @Environment(\.isDense) private var isDense

    private var track: ActivityTrack? {
        if case .loaded(let track) = model.tracks[workout.id] { track } else { nil }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if let track, !track.route.isEmpty {
                    RouteMapCard(
                        track: track, sport: workout.sport, zones: zones, selection: selection)
                }
                stats
                recording
                if workout.startPoint != nil, workout.distance != nil {
                    SimilarRoutesCard(workout: workout, model: model)
                }
                if workout.aerobicEffect != nil || workout.trainingLoad != nil {
                    effect
                }
                if !workout.heartRateZones.isEmpty {
                    ZoneCard(
                        title: "Heart Rate Zones", symbol: "heart.fill",
                        seconds: workout.heartRateZones, names: Self.heartRateZoneNames
                    ) { zones?.label(zone: $0) }
                }
                if !workout.powerZones.isEmpty {
                    ZoneCard(
                        title: "Power Zones", symbol: "bolt.fill",
                        seconds: Array(
                            workout.powerZones.prefix(
                                max(5, (workout.powerZones.lastIndex { $0 > 0 } ?? 0) + 1))),
                        tint: TrackMeasure.power.color)
                }
            }
            .padding()
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(workout.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.loadTrack(for: workout) }
        .toolbar {
            if workout.distance != nil || workout.startPoint != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu("Export", systemImage: "square.and.arrow.up") {
                        ShareLink(
                            item: RecordingFile(workout: workout, format: .fit, model: model),
                            preview: SharePreview(workout.name)
                        ) {
                            Label("Original Recording (FIT)", systemImage: "doc")
                        }
                        ShareLink(
                            item: RecordingFile(workout: workout, format: .gpx, model: model),
                            preview: SharePreview(workout.name)
                        ) {
                            Label("Route (GPX)", systemImage: "map")
                        }
                    }
                }
            }
        }
    }

    /// The charts, splits, laps and sets of the recording, as far as it is loaded.
    @ViewBuilder private var recording: some View {
        switch model.tracks[workout.id] {
        case .loaded(let track):
            if !track.samples.isEmpty {
                TrackChartsCard(
                    track: track, sport: workout.sport, zones: zones, selection: $selection)
            }
            if track.splits.count > 1 {
                SplitsCard(splits: track.splits, sport: workout.sport)
            }
            if track.laps.count > 1, !track.lapsRepeatSplits {
                LapsCard(laps: track.laps, sport: workout.sport)
            }
            if !SetsCard.logged(track.sets).isEmpty {
                SetsCard(sets: track.sets)
            }
        case .failed(let problem):
            VStack(alignment: .leading, spacing: 10) {
                Label(problem.title, systemImage: problem.symbol)
                    .font(.headline)
                Text(problem.message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Try Again") {
                    Task { await model.loadTrack(for: workout) }
                }
                .buttonStyle(.glass)
            }
            .cardStyle()
        case .unavailable:
            Label("No recording to analyze for this activity.", systemImage: "waveform.slash")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .cardStyle()
        case .loading, nil:
            HStack(spacing: 10) {
                ProgressView()
                Text("Loading the recording…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .cardStyle()
        }
    }

    private static let heartRateZoneNames = [
        String(localized: "Warm Up"), String(localized: "Easy"), String(localized: "Aerobic"),
        String(localized: "Threshold"), String(localized: "Maximum"),
    ]

    private var header: some View {
        HStack(spacing: 14) {
            SportIcon(sport: workout.sport, size: 52)
            VStack(alignment: .leading, spacing: 2) {
                Text(workout.name)
                    .font(.title2.weight(.bold))
                Text(
                    workout.start ?? workout.date.startOfDay(in: .current),
                    format: .dateTime.weekday(.wide).day().month(.wide).hour().minute()
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                if let location = workout.location {
                    Label(location, systemImage: "mappin.and.ellipse")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// The numbers Garmin recorded, in a grid.
    private var stats: some View {
        let speed = workout.averageSpeed.map {
            Format.pace(metresPerSecond: $0, sport: workout.sport)
        }
        let isPace = [.running, .walking, .swimming].contains(workout.sport)
        let cadenceUnit = workout.sport == .cycling ? "rpm" : "spm"
        let items: [(label: String, value: String?)] = [
            (String(localized: "Duration"), Format.clock(seconds: workout.duration)),
            (String(localized: "Distance"), workout.distance.map(Format.distance)),
            (isPace ? String(localized: "Pace") : String(localized: "Speed"), speed),
            (String(localized: "Avg Heart Rate"), workout.averageHeartRate.map(Self.bpm)),
            (String(localized: "Max Heart Rate"), workout.maxHeartRate.map(Self.bpm)),
            (String(localized: "Elevation Gain"), workout.elevationGain.map(Format.elevation)),
            (String(localized: "Avg Power"), workout.averagePower.map { "\(Int($0.rounded())) W" }),
            (
                String(localized: "Normalized Power"),
                workout.normalizedPower.map { "\(Int($0.rounded())) W" }
            ),
            (
                String(localized: "Cadence"),
                workout.cadence.map { "\(Int($0.rounded())) \(cadenceUnit)" }
            ),
            (
                String(localized: "Calories"),
                workout.calories.map { "\(Int($0.rounded()).formatted()) kcal" }
            ),
        ]
        return LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: isDense ? 3 : 2),
            spacing: 8
        ) {
            ForEach(
                items.compactMap { label, value in value.map { Stat(label: label, value: $0) } }
            ) {
                StatTile(stat: $0)
            }
        }
    }

    private static func bpm(_ value: Double) -> String {
        "\(Int(value.rounded())) bpm"
    }

    /// Garmin's training effect and training load.
    private var effect: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardHeader(
                title: "Training Effect", symbol: "flame.fill", tint: ColorRole.zone(3).color)
            if let aerobic = workout.aerobicEffect {
                EffectGauge(
                    title: "Aerobic", value: aerobic,
                    message: Format.trainingMessage(workout.aerobicMessage))
            }
            if let anaerobic = workout.anaerobicEffect {
                EffectGauge(
                    title: "Anaerobic", value: anaerobic,
                    message: Format.trainingMessage(workout.anaerobicMessage))
            }
            HStack(spacing: 24) {
                if let benefit = Format.benefit(workout.primaryBenefit) {
                    LabeledValue(title: "Primary Benefit", value: benefit)
                }
                if let load = workout.trainingLoad {
                    LabeledValue(title: "Training Load", value: "\(Int(load.rounded()))")
                }
            }
            Text(
                """
                Training effect rates the impact on your aerobic and anaerobic fitness from 0 \
                to 5. Training load is the oxygen debt (EPOC) Garmin estimates for the \
                activity; it adds to your fitness and fatigue.
                """
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .cardStyle()
    }
}

/// A training effect from 0 to 5 with Garmin's words for it.
private struct EffectGauge: View {
    let title: LocalizedStringKey
    let value: Double
    let message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.subheadline.weight(.semibold))
                Spacer()
                Text(value.formatted(.number.precision(.fractionLength(1))))
                    .font(.title3.weight(.bold).monospacedDigit())
                Text(Format.trainingEffect(value))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            EffectBar(share: min(1, max(0, value / 5)))
            if let message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A training effect's share of the scale, on a bar shaded from easy to hard.
private struct EffectBar: View {
    let share: Double

    var body: some View {
        Capsule()
            .fill(Color.secondary.opacity(0.2))
            .frame(height: 8)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    ZoneStyle.colors[1], ZoneStyle.colors[2], ZoneStyle.colors[3],
                                ],
                                startPoint: .leading, endPoint: .trailing)
                        )
                        .frame(width: proxy.size.width * share)
                }
            }
    }
}

/// A caption above a value.
private struct LabeledValue: View {
    let title: LocalizedStringKey
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.headline)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Time in each zone, the most intense on top.
private struct ZoneCard: View {
    let title: LocalizedStringKey
    let symbol: String
    let seconds: [Double]
    var tint = TrackMeasure.heartRate.color
    var names: [String] = []
    var detail: (Int) -> String? = { _ in nil }

    private static var colors: [Color] { ZoneStyle.colors }

    /// `7:30 · 15%`.
    private static func time(_ seconds: Double, of total: Double) -> String {
        let share = (seconds / total).formatted(.percent.precision(.fractionLength(0)))
        return "\(Format.clock(seconds: seconds)) · \(share)"
    }

    var body: some View {
        let total = max(1, seconds.reduce(0, +))
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: title, symbol: symbol, tint: tint)
            ForEach(Array(seconds.indices.reversed()), id: \.self) { index in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Zone \(index + 1)").font(.subheadline.weight(.semibold))
                        if index < names.count {
                            Text(names[index]).font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(Self.time(seconds[index], of: total))
                            .font(.subheadline.monospacedDigit())
                    }
                    ProgressView(value: seconds[index] / total)
                        .tint(Self.colors[index % Self.colors.count])
                    if let detail = detail(index) {
                        Text(detail).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .cardStyle()
    }
}

/// A named number in the stats grid.
private struct Stat: Identifiable {
    let label: String
    let value: String

    var id: String { label }
}

/// A stat on a rounded tile.
private struct StatTile: View {
    let stat: Stat

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(stat.label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(stat.value)
                .font(.title3.weight(.semibold).monospacedDigit())
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }
}
