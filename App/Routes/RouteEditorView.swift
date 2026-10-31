import MapKit
import SwiftUI

/// Planning a route on the map: tap to place points, drag them to move them; the route follows
/// roads and paths.
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
    /// The point being dragged, and how far.
    @State private var drag: (index: Int, offset: CGSize)?
    /// The leg whose middle is being dragged to make a new point, and how far.
    @State private var legDrag: (index: Int, offset: CGSize)?
    @Environment(\.dismiss) private var dismiss

    /// Where the drags of points are measured, to find the map coordinate they end on.
    private static let mapSpace = "routeMap"
    /// The color of past routes: Okabe and Ito's reddish purple, faint, apart from the route
    /// being planned.
    private static let myRoutesColor = Color(red: 0.8, green: 0.475, blue: 0.655)

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
                legHandles(proxy: proxy)
                waypointMarkers(proxy: proxy)
            }
            .coordinateSpace(.named(Self.mapSpace))
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

    /// The middle of every leg, where a new point can be pulled out.
    @MapContentBuilder
    private func legHandles(proxy: MapProxy) -> some MapContent {
        ForEach(planner.route.legs.indices, id: \.self) { index in
            if let middle = planner.route.midpoint(ofLeg: index) {
                Annotation(
                    "Add a Point", coordinate: middle.coordinate, anchor: .center
                ) {
                    legHandle(index, at: middle, proxy: proxy)
                }
                .annotationTitles(.hidden)
            }
        }
    }

    /// The route's points.
    @MapContentBuilder
    private func waypointMarkers(proxy: MapProxy) -> some MapContent {
        ForEach(Array(planner.waypoints.enumerated()), id: \.offset) { index, point in
            Annotation("Point \(index + 1)", coordinate: point.coordinate, anchor: .center) {
                waypoint(index, proxy: proxy)
            }
            .annotationTitles(.hidden)
        }
    }

    /// The middle of leg `index`: drag it, or click it, to put a new point between the leg's
    /// ends there.
    private func legHandle(_ index: Int, at middle: GeoPoint, proxy: MapProxy) -> some View {
        Circle()
            .fill(Color.white.opacity(0.85))
            .stroke(Color.accentColor, lineWidth: 2)
            .frame(width: 12, height: 12)
            .padding(6)
            .contentShape(.circle)
            .offset(legDrag?.index == index ? legDrag?.offset ?? .zero : .zero)
            .highPriorityGesture(
                DragGesture(coordinateSpace: .named(Self.mapSpace))
                    .onChanged { value in legDrag = (index, value.translation) }
                    .onEnded { value in
                        legDrag = nil
                        guard
                            let coordinate = proxy.convert(
                                value.location, from: .named(Self.mapSpace))
                        else { return }
                        Task {
                            await planner.insert(
                                GeoPoint(
                                    latitude: coordinate.latitude, longitude: coordinate.longitude),
                                at: index + 1)
                        }
                    }
            )
            .onTapGesture {
                Task { await planner.insert(middle, at: index + 1) }
            }
            .accessibilityLabel(Text("Add a Point"))
            .accessibilityAddTraits(.isButton)
    }

    /// A point of the route: the start flagged, the others white; drag it to move it, and remove
    /// it from its menu.
    private func waypoint(_ index: Int, proxy: MapProxy) -> some View {
        let isStart = index == 0
        return ZStack {
            Circle()
                .fill(isStart ? Color.green : Color.white)
                .stroke(Color.black.opacity(0.6), lineWidth: 2)
                .frame(width: isStart ? 22 : 16, height: isStart ? 22 : 16)
            if isStart {
                Image(systemName: "flag.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .offset(drag?.index == index ? drag?.offset ?? .zero : .zero)
        .highPriorityGesture(
            DragGesture(coordinateSpace: .named(Self.mapSpace))
                .onChanged { value in drag = (index, value.translation) }
                .onEnded { value in
                    drag = nil
                    guard
                        let coordinate = proxy.convert(value.location, from: .named(Self.mapSpace))
                    else { return }
                    Task {
                        await planner.move(
                            at: index,
                            to: GeoPoint(
                                latitude: coordinate.latitude, longitude: coordinate.longitude))
                    }
                }
        )
        .contextMenu {
            Button("Remove Point", systemImage: "trash", role: .destructive) {
                Task { await planner.remove(at: index) }
            }
        }
        .accessibilityLabel(isStart ? Text("Start") : Text("Point \(index + 1)"))
        .accessibilityAction(named: Text("Remove Point")) {
            Task { await planner.remove(at: index) }
        }
    }

    /// Recent activities' routes, faint, under the route being planned.
    @MapContentBuilder private var myRoutesLayer: some MapContent {
        if showsMyRoutes {
            ForEach(Array(myRoutes.enumerated()), id: \.offset) { _, route in
                MapPolyline(coordinates: route.map(\.coordinate))
                    .stroke(
                        Self.myRoutesColor.opacity(0.5),
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
            Text(Self.hint)
                .font(.footnote)
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
            ? String(localized: "No points yet.")
            : RouteEditorView.summary(of: planner.route, usualSpeed: usualSpeed)
    }

    /// How planning works, with the Mac's pointer or a finger.
    static var hint: String {
        ProcessInfo.processInfo.isMacCatalystApp
            ? String(
                localized: """
                    Click the map to add a point; the route follows roads and paths to it. Drag a \
                    point to move it, right-click it to remove it; drag the dot in the middle of a \
                    stretch to bend the route through a new point.
                    """)
            : String(
                localized: """
                    Tap the map to add a point; the route follows roads and paths to it. Drag a \
                    point to move it, touch and hold it to remove it; drag the dot in the middle \
                    of a stretch to bend the route through a new point.
                    """)
    }

    private var followsPaths: Binding<Bool> {
        Binding {
            planner.followsPaths
        } set: { follows in
            Task { await planner.setFollowsPaths(follows) }
        }
    }
}

/// Undo, back to start, reverse, clear and export, with their names where there is room.
private struct RouteControls: View {
    let planner: RoutePlanner
    let usualSpeed: Double?

    var body: some View {
        ViewThatFits(in: .horizontal) {
            buttons.labelStyle(.titleAndIcon)
            buttons.labelStyle(.iconOnly)
        }
        .buttonStyle(.glass)
        .controlSize(DeskStyle.controlSize)
    }

    private var buttons: some View {
        HStack {
            Button("Undo", systemImage: "arrow.uturn.backward") { planner.undo() }
                .disabled(planner.waypoints.isEmpty)
            Button("Back to Start", systemImage: "arrow.trianglehead.counterclockwise") {
                Task { await planner.closeLoop() }
            }
            .disabled(planner.waypoints.count < 2 || planner.route.isLoop)
            Button("Reverse", systemImage: "arrow.left.arrow.right") { planner.reverse() }
                .disabled(planner.waypoints.count < 2)
            Button("Clear", systemImage: "xmark", role: .destructive) { planner.clear() }
                .disabled(planner.waypoints.isEmpty)
            Spacer(minLength: 8)
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
    }
}

extension GeoPoint {
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
