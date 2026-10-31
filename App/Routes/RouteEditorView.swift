import MapKit
import SwiftUI

/// Planning a route on the map: tap to place points; the route follows roads and paths.
struct RouteEditorView: View {
    let library: RouteLibrary
    let usualSpeed: Double?
    /// The routes of recent activities, to plan along, and how to load them.
    let myRoutes: [[GeoPoint]]
    let loadMyRoutes: (() async -> Void)?
    @AppStorage("routes.showsMyRoutes") private var showsMyRoutes = true
    @State private var planner: RoutePlanner
    @State private var position: MapCameraPosition
    @State private var name: String
    @Environment(\.dismiss) private var dismiss

    init(
        route: PlannedRoute, library: RouteLibrary, home: GeoPoint?, usualSpeed: Double?,
        myRoutes: [[GeoPoint]] = [],
        loadMyRoutes: (() async -> Void)? = nil
    ) {
        self.library = library
        self.usualSpeed = usualSpeed
        self.myRoutes = myRoutes
        self.loadMyRoutes = loadMyRoutes
        _planner = State(initialValue: RoutePlanner(router: MapsRouter(), route: route))
        _name = State(initialValue: route.name)
        let center = route.waypoints.first ?? home
        _position = State(
            initialValue: route.waypoints.isEmpty
                ? center.map {
                    .region(
                        MKCoordinateRegion(
                            center: $0.coordinate,
                            span: MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.03)))
                } ?? .automatic
                : .automatic)
    }

    var body: some View {
        MapReader { proxy in
            Map(position: $position) {
                myRoutesLayer
                MapPolyline(coordinates: planner.route.path.map(\.coordinate))
                    .stroke(
                        .tint, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                ForEach(Array(planner.waypoints.enumerated()), id: \.offset) { index, point in
                    Annotation("Point \(index + 1)", coordinate: point.coordinate, anchor: .center)
                    {
                        Circle()
                            .fill(index == 0 ? Color.green : Color.white)
                            .stroke(Color.primary.opacity(0.7), lineWidth: 2)
                            .frame(width: 14, height: 14)
                    }
                    .annotationTitles(.hidden)
                }
            }
            .mapStyle(RouteMap.style(Preferences.shared.settings.mapStyle))
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Places a point of the route")
            .onTapGesture { location in
                guard let coordinate = proxy.convert(location, from: .local) else { return }
                Task {
                    await planner.add(
                        GeoPoint(latitude: coordinate.latitude, longitude: coordinate.longitude))
                }
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .safeAreaInset(edge: .bottom) {
            RoutePanel(
                planner: planner, name: $name, usualSpeed: usualSpeed,
                showsMyRoutes: $showsMyRoutes
            )
            .padding()
            .readableWidth(640)
        }
        .task(id: showsMyRoutes) {
            if showsMyRoutes {
                await loadMyRoutes?()
            }
        }
        .navigationTitle(name.isEmpty ? String(localized: "New Route") : name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", systemImage: "checkmark") {
                    planner.rename(name)
                    library.save(planner.route)
                    dismiss()
                }
                .disabled(planner.waypoints.count < 2)
            }
        }
    }

    /// Recent activities' routes, faint, under the route being planned.
    @MapContentBuilder private var myRoutesLayer: some MapContent {
        if showsMyRoutes {
            ForEach(Array(myRoutes.enumerated()), id: \.offset) { _, route in
                MapPolyline(coordinates: route.map(\.coordinate))
                    .stroke(
                        Color.secondary.opacity(0.55),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            }
        }
    }

    /// `8.4 km · about 43 min at your usual pace`.
    static func summary(of route: PlannedRoute, usualSpeed: Double?) -> String {
        let distance = Format.distance(metres: route.distance)
        guard let usualSpeed, usualSpeed > 0, route.distance > 0 else { return distance }
        let time = Format.hours(seconds: route.distance / usualSpeed)
        return String(localized: "\(distance) · about \(time) at your usual pace")
    }
}

/// The route's numbers and the planning controls, on glass over the map.
private struct RoutePanel: View {
    let planner: RoutePlanner
    @Binding var name: String
    let usualSpeed: Double?
    @Binding var showsMyRoutes: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TextField("Route name", text: $name)
                    .font(.headline)
                if planner.isRouting {
                    ProgressView()
                }
            }
            Text(summary)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
            Toggle("Follow Roads and Paths", isOn: followsPaths)
                .font(.subheadline)
            Toggle("Show My Routes", isOn: $showsMyRoutes)
                .font(.subheadline)
            if let problem = planner.problem {
                Label(problem.message, systemImage: problem.symbol)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            RouteControls(planner: planner, usualSpeed: usualSpeed)
        }
        .padding()
        .glassEffect(in: .rect(cornerRadius: 24))
    }

    private var summary: String {
        planner.waypoints.isEmpty
            ? String(localized: "Tap the map to place the start.")
            : RouteEditorView.summary(of: planner.route, usualSpeed: usualSpeed)
    }

    private var followsPaths: Binding<Bool> {
        Binding {
            planner.followsPaths
        } set: { follows in
            Task { await planner.setFollowsPaths(follows) }
        }
    }
}

/// Undo, back to start, reverse and export.
private struct RouteControls: View {
    let planner: RoutePlanner
    let usualSpeed: Double?

    var body: some View {
        HStack {
            Button("Undo", systemImage: "arrow.uturn.backward") { planner.undo() }
                .disabled(planner.waypoints.isEmpty)
            Button("Back to Start", systemImage: "arrow.trianglehead.counterclockwise") {
                Task { await planner.closeLoop() }
            }
            .disabled(planner.waypoints.count < 2 || planner.route.isLoop)
            Button("Reverse", systemImage: "arrow.left.arrow.right") { planner.reverse() }
                .disabled(planner.waypoints.count < 2)
            Spacer()
            Menu("Export", systemImage: "square.and.arrow.up") {
                ShareLink(
                    item: RouteCourseFile(route: planner.route, speed: usualSpeed ?? 3),
                    preview: SharePreview(planner.route.title)
                ) {
                    Label("Course for Garmin (FIT)", systemImage: "applewatch")
                }
                ShareLink(
                    item: RouteFile(route: planner.route),
                    preview: SharePreview(planner.route.title)
                ) {
                    Label("Export GPX", systemImage: "map")
                }
            }
            .disabled(planner.waypoints.count < 2)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.glass)
    }
}

extension GeoPoint {
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
