import Foundation
import Testing

@testable import GCPAPISyncApp

/// A router that detours through a point between the two, and counts its requests.
private final class DetourRouter: Router {
    private let counter = RequestCounter()

    var requests: Int {
        get async { await counter.count }
    }

    func path(from start: GeoPoint, to end: GeoPoint) async -> [GeoPoint] {
        await counter.increment()
        let detour = GeoPoint(
            latitude: (start.latitude + end.latitude) / 2 + 0.001,
            longitude: (start.longitude + end.longitude) / 2)
        return [start, detour, end]
    }

    private actor RequestCounter {
        var count = 0

        func increment() {
            count += 1
        }
    }
}

/// A router that cannot find a path.
private struct FailingRouter: Router {
    func path(from _: GeoPoint, to _: GeoPoint) throws -> [GeoPoint] {
        throw Problem.offline
    }
}

@Suite struct PlannedRouteTests {
    private let start = GeoPoint(latitude: 47.36, longitude: 8.54)
    private let east = GeoPoint(latitude: 47.36, longitude: 8.55)
    private let north = GeoPoint(latitude: 47.37, longitude: 8.55)

    @Test func pathsJoinTheirLegs() {
        let route = PlannedRoute(
            waypoints: [start, east, north], legs: [[start, east], [east, north]])
        #expect(route.path == [start, east, north])
        #expect(abs(route.distance - (start.distance(to: east) + east.distance(to: north))) < 1e-6)
        #expect(!route.isLoop)
        #expect(PlannedRoute(waypoints: [start]).path == [start])
        #expect(PlannedRoute().path.isEmpty)
        #expect(PlannedRoute().distance == 0)
    }

    @Test func gpxCarriesThePath() {
        let route = PlannedRoute(
            name: "Hills & Lake", waypoints: [start, east], legs: [[start, east]])
        let gpx = route.gpx()
        #expect(gpx.contains("<name>Hills &amp; Lake</name>"))
        #expect(gpx.components(separatedBy: "<trkpt").count - 1 == 2)
        #expect(gpx.contains(#"lat="47.36" lon="8.54""#))
        #expect(PlannedRoute().gpx().contains(String(localized: "Planned Route")))
    }

    @Test func routesAreSavedAndRestored() {
        let file = URL.temporaryDirectory.appending(path: "routes-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let store = RouteStore(file: file)
        #expect(store.load().isEmpty)
        let library = RouteLibrary(store: store)
        let route = PlannedRoute(name: "Loop", waypoints: [start, east], legs: [[start, east]])
        library.save(route)
        var renamed = route
        renamed.name = "Lake Loop"
        library.save(renamed)
        #expect(RouteLibrary(store: store).routes == [renamed])
        library.delete(renamed)
        #expect(store.load().isEmpty)
        #expect(RouteLibrary(store: nil).routes.isEmpty)
    }
}

@Suite struct RoutePlannerTests {
    private let start = GeoPoint(latitude: 47.36, longitude: 8.54)
    private let east = GeoPoint(latitude: 47.36, longitude: 8.55)
    private let north = GeoPoint(latitude: 47.37, longitude: 8.55)

    @Test func pointsAreJoinedAlongPaths() async {
        let router = DetourRouter()
        let planner = RoutePlanner(router: router)
        await planner.add(start)
        #expect(planner.route.path == [start])
        await planner.add(east)
        await planner.add(north)
        #expect(planner.waypoints == [start, east, north])
        #expect(planner.route.legs.count == 2)
        #expect(planner.route.path.count == 5)
        #expect(planner.route.path.first == start)
        #expect(planner.route.path.last == north)
        #expect(planner.distance > start.distance(to: east) + east.distance(to: north))
        #expect(await router.requests == 2)
    }

    @Test func undoLoopReverseAndClear() async {
        let planner = RoutePlanner(router: StraightRouter())
        await planner.add(start)
        await planner.add(east)
        await planner.add(north)
        planner.undo()
        #expect(planner.waypoints == [start, east])
        #expect(planner.route.legs.count == 1)
        await planner.closeLoop()
        #expect(planner.route.isLoop)
        #expect(planner.waypoints == [start, east, start])
        // A loop is not closed twice.
        await planner.closeLoop()
        #expect(planner.waypoints.count == 3)
        planner.reverse()
        #expect(planner.route.path == [start, east, start].reversed())
        planner.rename("Out and back")
        #expect(planner.route.name == "Out and back")
        planner.clear()
        #expect(planner.waypoints.isEmpty)
        planner.undo()
        #expect(planner.waypoints.isEmpty)
    }

    @Test func straightLinesAskNobody() async {
        let router = DetourRouter()
        let planner = RoutePlanner(router: router)
        await planner.setFollowsPaths(false)
        await planner.add(start)
        await planner.add(east)
        #expect(planner.route.path == [start, east])
        #expect(await router.requests == 0)
        await planner.setFollowsPaths(true)
        #expect(planner.route.path.count == 3)
        #expect(await router.requests == 1)
    }

    @Test func aLegWithoutAPathStaysStraight() async {
        let planner = RoutePlanner(router: FailingRouter())
        await planner.add(start)
        await planner.add(east)
        #expect(planner.route.path == [start, east])
        #expect(planner.problem == .offline)
    }

    @Test func estimatesUseTheUsualPace() {
        let route = PlannedRoute(waypoints: [start, east], legs: [[start, east]])
        #expect(
            RouteEditorView.summary(of: route, usualSpeed: nil)
                == Format.distance(metres: route.distance))
        #expect(
            RouteEditorView.summary(of: route, usualSpeed: 3).contains(
                Format.hours(seconds: route.distance / 3)))
    }
}
