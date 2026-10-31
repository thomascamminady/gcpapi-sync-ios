import CoreLocation
import MapKit
import SwiftUI

/// The colors of heart rate (and power) zones, from easy to all-out.
enum ZoneStyle {
    /// The zones' colors, as the user chose them.
    static var colors: [Color] {
        (0..<7).map { ColorRole.zone($0).color }
    }

    static func color(zone: Int?, fallback: Color) -> Color {
        zone.map { colors[min($0, colors.count - 1)] } ?? fallback
    }
}

/// The route on a map, colored by heart rate zone, with the scrubbed position marked.
struct RouteMap: View {
    let track: ActivityTrack
    let sport: Sport
    let zones: HeartRateZoneSet?
    var selection: Double?
    var interactive = false

    /// Steps of heart rate on the color map: enough to look continuous.
    static let levels = 24

    var body: some View {
        let settings = Preferences.shared.settings
        Map(initialPosition: .automatic, interactionModes: interactive ? .all : []) {
            ForEach(segments(settings.routeColoring)) { segment in
                MapPolyline(coordinates: segment.points.map(\.coordinate))
                    .stroke(
                        color(segment, settings.routeColoring),
                        style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            }
            markers
        }
        .mapStyle(Self.style(settings.mapStyle))
    }

    private func segments(_ coloring: Settings.RouteColoring) -> [ActivityTrack.Segment] {
        switch coloring {
        case .heartRateZone: track.segments(zones: zones)
        case .heartRate: track.segments(heartRateLevels: Self.levels)
        case .sport: track.segments(zones: nil)
        }
    }

    private func color(
        _ segment: ActivityTrack.Segment, _ coloring: Settings.RouteColoring
    )
        -> Color
    {
        switch coloring {
        case .heartRateZone:
            return ZoneStyle.color(zone: segment.zone, fallback: sport.color)
        case .heartRate:
            guard let level = segment.zone else { return sport.color }
            return Preferences.shared.valueColor((Double(level) + 0.5) / Double(Self.levels))
        case .sport:
            return sport.color
        }
    }

    static func style(_ style: Settings.MapStyle) -> MapStyle {
        switch style {
        case .standard: .standard(elevation: .realistic, pointsOfInterest: .excludingAll)
        case .hybrid: .hybrid(elevation: .realistic, pointsOfInterest: .excludingAll)
        case .satellite: .imagery(elevation: .realistic)
        }
    }

    /// Start, finish and the scrubbed position.
    @MapContentBuilder private var markers: some MapContent {
        if let first = track.route.first {
            Annotation("Start", coordinate: first.coordinate, anchor: .center) {
                Circle()
                    .fill(.green)
                    .stroke(.white, lineWidth: 2)
                    .frame(width: 14, height: 14)
            }
            .annotationTitles(.hidden)
        }
        if let last = track.route.last {
            Annotation(String(localized: "Finish"), coordinate: last.coordinate, anchor: .center) {
                Image(systemName: "flag.checkered.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.white, .black)
                    .accessibilityHidden(true)
            }
            .annotationTitles(.hidden)
        }
        if let selection, let point = track.point(near: selection) {
            Annotation("Selected", coordinate: point.coordinate, anchor: .center) {
                Circle()
                    .fill(.white)
                    .stroke(Color.primary, lineWidth: 3)
                    .frame(width: 16, height: 16)
                    .shadow(radius: 2)
            }
            .annotationTitles(.hidden)
        }
    }
}

/// The route map on the activity screen, which opens a full-screen map.
struct RouteMapCard: View {
    let track: ActivityTrack
    let sport: Sport
    let zones: HeartRateZoneSet?
    var selection: Double?
    @State private var showsFullMap = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            RouteMap(track: track, sport: sport, zones: zones, selection: selection)
                .chartHeight(260)
                .clipShape(.rect(cornerRadius: 20))
                .overlay(alignment: .topTrailing) {
                    Button("Expand Map", systemImage: "arrow.up.left.and.arrow.down.right") {
                        showsFullMap = true
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.glass)
                    .padding(10)
                }
                .accessibilityLabel("Route map")
            switch Preferences.shared.settings.routeColoring {
            case .heartRateZone where zones != nil:
                ZoneLegend()
            case .heartRate:
                if let range = track.heartRateRange {
                    ValueLegend(
                        title: String(localized: "Heart rate"),
                        low: Format.heartRate(range.lowerBound),
                        high: Format.heartRate(range.upperBound))
                }
            default:
                EmptyView()
            }
        }
        .fullScreenCover(isPresented: $showsFullMap) {
            NavigationStack {
                RouteMap(track: track, sport: sport, zones: zones, interactive: true)
                    .ignoresSafeArea(edges: .bottom)
                    .navigationTitle("Route")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done", systemImage: "checkmark") { showsFullMap = false }
                        }
                    }
            }
        }
    }
}

/// What the route's colors mean.
struct ZoneLegend: View {
    var body: some View {
        HStack(spacing: 10) {
            Text("Heart rate zone")
            ForEach(0..<5, id: \.self) { zone in
                HStack(spacing: 3) {
                    Capsule().fill(ZoneStyle.colors[zone]).frame(width: 12, height: 4)
                    Text("\(zone + 1)")
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }
}

extension ActivityTrack.Point {
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

/// What colors on the color map mean: a gradient from the lowest value to the highest.
struct ValueLegend: View {
    let title: String
    let low: String
    let high: String

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
            Text(low)
                .monospacedDigit()
            Capsule()
                .fill(Preferences.shared.valueGradient)
                .frame(width: 80, height: 6)
            Text(high)
                .monospacedDigit()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }
}
