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

/// A router whose paths run along east–west roads at every thousandth of a degree plus half,
/// from the nearest to each point: points on a road stay where they are.
private struct RoadRouter: Router {
    static func road(_ point: GeoPoint) -> GeoPoint {
        GeoPoint(
            latitude: (point.latitude * 1000).rounded(.down) / 1000 + 0.0005,
            longitude: point.longitude)
    }

    func path(from start: GeoPoint, to end: GeoPoint) -> [GeoPoint] {
        [Self.road(start), Self.road(end)]
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

    @Test func fitCoursesFollowThePath() throws {
        let route = PlannedRoute(
            name: "Zürichsee Runde, lang", waypoints: [start, east, north],
            legs: [[start, east], [east, north]])
        let begin = FITActivity.epoch.addingTimeInterval(1_100_000_000)
        let data = route.fitCourse(speed: 4, start: begin)
        let course = try FITActivity(decoding: data)
        #expect(course.records.count == 3)
        for (record, point) in zip(course.records, route.path) {
            #expect(abs((record.latitude ?? 0) - point.latitude) < 1e-6)
            #expect(abs((record.longitude ?? 0) - point.longitude) < 1e-6)
        }
        let distance = try #require(course.records.last?.distance)
        #expect(abs(distance - route.distance) < 0.01)
        // Timed at 4 m/s from the start.
        let seconds = try #require(course.records.last?.time.timeIntervalSince(begin))
        #expect(abs(seconds - route.distance / 4) <= 1)
        #expect(course.timerEvents.map(\.isStart) == [true, false])
        // The name is cut to 15 bytes without breaking a character ("Zürichsee Rund" is 15),
        // ends with a zero, and running follows.
        let name = Data("Zürichsee Rund".utf8) + Data([0, 1])
        #expect(data.contains(name))
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

    @Test func pointsMoveOntoTheRoad() async {
        let planner = RoutePlanner(router: RoadRouter())
        await planner.add(start)
        await planner.add(east)
        await planner.add(north)
        let road = RoadRouter.road
        // Every point lies where its legs begin and end: no spurs off the road.
        #expect(planner.waypoints == [road(start), road(east), road(north)])
        #expect(planner.route.legs.map(\.first) == [road(start), road(east)])
        #expect(planner.route.legs.map(\.last) == [road(east), road(north)])
    }

    @Test func pointsMoveAndGo() async {
        let router = DetourRouter()
        let planner = RoutePlanner(router: router)
        let west = GeoPoint(latitude: 47.36, longitude: 8.53)
        for point in [start, east, north] {
            await planner.add(point)
        }
        await planner.move(at: 1, to: west)
        #expect(planner.waypoints == [start, west, north])
        #expect(planner.route.legs.map(\.first) == [start, west])
        #expect(planner.route.legs.map(\.last) == [west, north])
        // Both legs of the moved point are found again.
        #expect(await router.requests == 4)
        await planner.remove(at: 1)
        #expect(planner.waypoints == [start, north])
        #expect(planner.route.legs.count == 1)
        #expect(planner.route.path.first == start)
        #expect(planner.route.path.last == north)
        await planner.remove(at: 0)
        #expect(planner.waypoints == [north])
        #expect(planner.route.legs.isEmpty)
        await planner.remove(at: 5)
        await planner.remove(at: 0)
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
