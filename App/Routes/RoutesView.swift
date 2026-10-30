import CoreTransferable
import GCPAPISync
import MapKit
import SwiftUI
import UniformTypeIdentifiers

/// A screen the routes tab opens.
enum RouteScreen: Hashable {
    case new
    case edit(PlannedRoute)
}

/// The routes tab: the planned routes, and planning new ones.
struct RoutesView: View {
    static let symbol = "point.topleft.down.to.point.bottomright.curvepath"

    let library: RouteLibrary
    /// Where new routes start, and the usual running speed for time estimates.
    let home: GeoPoint?
    let usualSpeed: Double?
    @State private var path: [RouteScreen] = []

    var body: some View {
        NavigationStack(path: $path) {
            routeList
                .navigationTitle("Routes")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("New Route", systemImage: "plus") { path.append(.new) }
                    }
                }
                .navigationDestination(for: RouteScreen.self) { screen in
                    switch screen {
                    case .new:
                        RouteEditorView(
                            route: PlannedRoute(), library: library, home: home,
                            usualSpeed: usualSpeed)
                    case .edit(let route):
                        RouteEditorView(
                            route: route, library: library, home: home, usualSpeed: usualSpeed)
                    }
                }
        }
    }
}

extension RoutesView {
    /// The saved routes, or how to plan one.
    var routeList: some View {
        List {
            ForEach(library.routes) { route in
                NavigationLink(value: RouteScreen.edit(route)) {
                    RouteRow(route: route, usualSpeed: usualSpeed)
                }
            }
            .onDelete { offsets in
                offsets.map { library.routes[$0] }.forEach(library.delete)
            }
        }
        .overlay {
            if library.routes.isEmpty {
                ContentUnavailableView {
                    Label("No Routes", systemImage: Self.symbol)
                } description: {
                    Text(
                        """
                        Tap the map to place points; the route follows roads and paths between \
                        them. Save it, or export it to Garmin Connect as a course.
                        """)
                } actions: {
                    Button("Plan a Route") { path = [.new] }
                        .buttonStyle(.glassProminent)
                }
            }
        }
    }
}

/// A saved route: its name, length and when it was planned.
private struct RouteRow: View {
    let route: PlannedRoute
    let usualSpeed: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(route.name.isEmpty ? String(localized: "Planned Route") : route.name)
                .font(.body.weight(.semibold))
            Text(RouteEditorView.summary(of: route, usualSpeed: usualSpeed))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A planned route as a GPX file.
struct RouteFile: Transferable {
    let route: PlannedRoute

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .xml) { file in
            Data(file.route.gpx().utf8)
        }
        .suggestedFileName { file in
            "\(file.route.name.isEmpty ? String(localized: "Planned Route") : file.route.name).gpx"
        }
    }
}
