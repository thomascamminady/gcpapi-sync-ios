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

    var body: some View {
        let settings = Preferences.shared.settings
        let segments = track.segments(zones: settings.routeColoring == .heartRateZone ? zones : nil)
        Map(initialPosition: .automatic, interactionModes: interactive ? .all : []) {
            ForEach(segments) { segment in
                MapPolyline(coordinates: segment.points.map(\.coordinate))
                    .stroke(
                        ZoneStyle.color(zone: segment.zone, fallback: sport.color),
                        style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            }
            markers
        }
        .mapStyle(Self.style(settings.mapStyle))
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
            Annotation("Finish", coordinate: last.coordinate, anchor: .center) {
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
            if zones != nil, Preferences.shared.settings.routeColoring == .heartRateZone {
                ZoneLegend()
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
