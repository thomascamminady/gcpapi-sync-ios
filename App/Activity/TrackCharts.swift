import Charts
import SwiftUI

/// A measurement the activity charts show, in the user's units.
enum TrackMeasure: String, CaseIterable, Identifiable {
    case heartRate
    case pace
    case elevation
    case cadence
    case power

    var id: Self { self }

    func title(for sport: Sport) -> String {
        switch self {
        case .heartRate: String(localized: "Heart Rate")
        case .pace:
            if Self.usesPace(sport) {
                String(localized: "Pace")
            } else {
                String(localized: "Speed")
            }
        case .elevation: String(localized: "Elevation")
        case .cadence: String(localized: "Cadence")
        case .power: String(localized: "Power")
        }
    }

    /// The measure's color, as the user chose it.
    var color: Color { ColorRole.measure(self).color }

    /// Heart rate in the resting heart rate's red; elevation in a neutral brown.
    var hue: Hue {
        switch self {
        case .heartRate: .red
        case .pace: .blue
        case .elevation: .brown
        case .cadence: .violet
        case .power: .orange
        }
    }

    /// Pace for running, walking and swimming; speed for everything else.
    static func usesPace(_ sport: Sport) -> Bool {
        [.running, .walking, .swimming].contains(sport)
    }

    /// The value to plot. Pace is plotted negated, in minutes, so that faster is higher.
    func value(_ sample: ActivityTrack.Sample, sport: Sport) -> Double? {
        switch self {
        case .heartRate:
            return sample.heartRate
        case .pace:
            guard let speed = sample.speed else { return nil }
            if Self.usesPace(sport) {
                // Slower than this is standing, not running.
                guard speed > (sport == .swimming ? 0.2 : 0.8) else { return nil }
                let unit = sport == .swimming ? 100 : (Format.usesMiles ? 1609.344 : 1000)
                return -unit / speed / 60
            }
            return speed * (Format.usesMiles ? 2.23694 : 3.6)
        case .elevation:
            return sample.altitude.map { Format.usesMiles ? $0 * 3.28084 : $0 }
        case .cadence:
            return sample.cadence
        case .power:
            return sample.power
        }
    }

    /// The plotted pace (negated minutes) or speed of `speed` metres per second.
    static func plotted(speed: Double, sport: Sport) -> Double {
        if usesPace(sport) {
            let unit = sport == .swimming ? 100 : (Format.usesMiles ? 1609.344 : 1000)
            return -unit / max(speed, 0.1) / 60
        }
        return speed * (Format.usesMiles ? 2.23694 : 3.6)
    }

    /// A plotted value as text with its unit.
    func format(_ value: Double, sport: Sport) -> String {
        switch self {
        case .heartRate:
            return "\(Int(value.rounded())) bpm"
        case .pace:
            if Self.usesPace(sport) {
                let unit = sport == .swimming ? "/100 m" : (Format.usesMiles ? "/mi" : "/km")
                return "\(Format.clock(seconds: -value * 60)) \(unit)"
            }
            let speed = value.formatted(.number.precision(.fractionLength(1)))
            return "\(speed) \(Format.usesMiles ? "mph" : "km/h")"
        case .elevation:
            return "\(Int(value.rounded())) \(Format.usesMiles ? "ft" : "m")"
        case .cadence:
            return "\(Int(value.rounded())) \(sport == .cycling ? "rpm" : "spm")"
        case .power:
            return "\(Int(value.rounded())) W"
        }
    }

    /// The axis label of a plotted value, without its unit.
    func axisLabel(_ value: Double, sport: Sport) -> String {
        self == .pace && Self.usesPace(sport)
            ? Format.clock(seconds: -value * 60) : Int(value.rounded()).formatted()
    }
}

/// Every measurement of a recording over time, scrubbed together.
struct TrackChartsCard: View {
    let track: ActivityTrack
    let sport: Sport
    let zones: HeartRateZoneSet?
    @Binding var selection: Double?

    private var measures: [TrackMeasure] {
        TrackMeasure.allCases.filter { measure in
            !Preferences.shared.settings.hiddenCharts.contains(measure.rawValue)
                && track.samples.contains { measure.value($0, sport: sport) != nil }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            CardHeader(
                title: "Analysis", symbol: "waveform.path.ecg", tint: TrackMeasure.heartRate.color)
            readout
            ForEach(measures) { measure in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(measure.title(for: sport))
                            .font(.caption.weight(.semibold))
                        Spacer()
                        if let average = average(measure) {
                            Text("Average \(measure.format(average, sport: sport))")
                                .font(.caption)
                        }
                    }
                    .foregroundStyle(.secondary)
                    TrackChart(
                        track: track, measure: measure, sport: sport,
                        zones: measure == .heartRate ? zones : nil, selection: $selection
                    )
                    .chartHeight(110)
                }
            }
        }
        .cardStyle()
    }

    private func average(_ measure: TrackMeasure) -> Double? {
        let values = track.samples.compactMap { measure.value($0, sport: sport) }
        return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    /// The values at the scrubbed moment, or how to scrub.
    @ViewBuilder private var readout: some View {
        if let selection, let sample = track.sample(near: selection) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), alignment: .leading)], spacing: 8)
            {
                ReadoutValue(title: "Time", value: Format.clock(seconds: sample.elapsed))
                if let distance = sample.distance, distance > 0 {
                    ReadoutValue(title: "Distance", value: Format.distance(metres: distance))
                }
                ForEach(measures) { measure in
                    if let value = measure.value(sample, sport: sport) {
                        ReadoutValue(
                            title: LocalizedStringKey(measure.title(for: sport)),
                            value: measure.format(value, sport: sport), color: measure.color)
                    }
                }
            }
            .contentTransition(.numericText())
        } else {
            Text("Drag across a chart to see every value at that moment, and where it was.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

/// A value at the scrubbed moment, under its name.
private struct ReadoutValue: View {
    let title: LocalizedStringKey
    let value: String
    var color: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.subheadline.weight(.semibold).monospacedDigit()).foregroundStyle(
                color)
        }
        .accessibilityElement(children: .combine)
    }
}

/// One measurement over time, with heart rate zones behind heart rate.
struct TrackChart: View {
    let track: ActivityTrack
    let measure: TrackMeasure
    let sport: Sport
    let zones: HeartRateZoneSet?
    @Binding var selection: Double?

    var body: some View {
        let points = track.samples.compactMap { sample in
            measure.value(sample, sport: sport).map { (elapsed: sample.elapsed, value: $0) }
        }
        let domain = Self.domain(points.map(\.value))
        Chart {
            if let zones {
                zoneBands(zones, domain: domain)
            }
            ForEach(points, id: \.elapsed) { point in
                series(point, domain: domain)
            }
            if let selection {
                RuleMark(x: .value("Selected", selection))
                    .foregroundStyle(Color.secondary.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
            }
        }
        .chartXSelection(value: $selection)
        .chartXScale(domain: 0...max(1, track.duration))
        .chartYScale(domain: domain)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let seconds = value.as(Double.self) {
                        Text(Format.clock(seconds: seconds))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let plotted = value.as(Double.self) {
                        Text(measure.axisLabel(plotted, sport: sport))
                    }
                }
            }
        }
    }

    /// The heart rate zones within `domain`, faintly.
    @ChartContentBuilder
    private func zoneBands(
        _ zones: HeartRateZoneSet, domain: ClosedRange<Double>
    )
        -> some ChartContent
    {
        ForEach(0..<zones.floors.count, id: \.self) { zone in
            let low = Double(zones.floors[zone])
            let high =
                zone + 1 < zones.floors.count
                ? Double(zones.floors[zone + 1]) : max(domain.upperBound, low)
            if high > domain.lowerBound, low < domain.upperBound {
                RectangleMark(
                    xStart: .value("Start", 0.0), xEnd: .value("End", track.duration),
                    yStart: .value("Low", max(low, domain.lowerBound)),
                    yEnd: .value("High", min(high, domain.upperBound))
                )
                .foregroundStyle(ZoneStyle.colors[zone].opacity(0.1))
            }
        }
    }

    /// A point of the line, over an area except for pace.
    @ChartContentBuilder
    private func series(
        _ point: (elapsed: Double, value: Double), domain: ClosedRange<Double>
    )
        -> some ChartContent
    {
        let value = min(max(point.value, domain.lowerBound), domain.upperBound)
        if measure != .pace {
            AreaMark(
                x: .value("Time", point.elapsed),
                yStart: .value("Base", domain.lowerBound),
                yEnd: .value(measure.title(for: sport), value)
            )
            .foregroundStyle(
                LinearGradient(
                    colors: [measure.color.opacity(0.25), measure.color.opacity(0)],
                    startPoint: .top, endPoint: .bottom))
        }
        LineMark(x: .value("Time", point.elapsed), y: .value(measure.title(for: sport), value))
            .foregroundStyle(measure.color)
            .lineStyle(StrokeStyle(lineWidth: 1.5, lineJoin: .round))
    }

    /// The range of the middle 96% of `values`, padded, so that a few outliers (a stop, a
    /// sensor glitch) do not flatten everything else.
    static func domain(_ values: [Double]) -> ClosedRange<Double> {
        let sorted = values.sorted()
        guard let first = sorted.first, let last = sorted.last else { return 0...1 }
        let low = sorted[Int(Double(sorted.count - 1) * 0.02)]
        let high = sorted[Int(Double(sorted.count - 1) * 0.98)]
        let padding = max((high - low) * 0.1, abs(high) * 0.02, 0.5)
        return max(first, low - padding)...min(last + padding, high + padding)
    }
}
