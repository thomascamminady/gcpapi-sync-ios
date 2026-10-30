import Foundation
import Observation

/// Editing a route: placing, undoing and reversing points, with the path found between them.
@Observable
final class RoutePlanner {
    private(set) var route: PlannedRoute
    private(set) var isRouting = false
    private(set) var problem: Problem?
    /// Whether legs follow roads and paths; straight lines ask nobody for directions.
    private(set) var followsPaths = true

    private let router: any Router

    init(router: any Router, route: PlannedRoute = PlannedRoute()) {
        self.route = route
        self.router = router
    }

    var waypoints: [GeoPoint] { route.waypoints }
    var distance: Double { route.distance }

    /// Add a point at the end and find the path to it.
    func add(_ point: GeoPoint) async {
        guard let previous = route.waypoints.last else {
            route.waypoints.append(point)
            return
        }
        route.waypoints.append(point)
        route.legs.append([previous, point])
        await findLeg(route.legs.count - 1)
    }

    /// Take back the last point.
    func undo() {
        guard !route.waypoints.isEmpty else { return }
        route.waypoints.removeLast()
        if !route.legs.isEmpty {
            route.legs.removeLast()
        }
    }

    /// Finish where the route started.
    func closeLoop() async {
        guard let first = route.waypoints.first, route.waypoints.count > 1, !route.isLoop else {
            return
        }
        await add(first)
    }

    /// Run the route the other way round.
    func reverse() {
        route.waypoints.reverse()
        route.legs = route.legs.reversed().map { $0.reversed() }
    }

    func clear() {
        route.waypoints = []
        route.legs = []
    }

    func rename(_ name: String) {
        route.name = name
    }

    /// Follow roads and paths, or draw straight lines, for every leg.
    func setFollowsPaths(_ follows: Bool) async {
        followsPaths = follows
        await reroute()
    }

    /// Find every leg again, as after switching between paths and straight lines.
    func reroute() async {
        route.legs = zip(route.waypoints, route.waypoints.dropFirst()).map { [$0, $1] }
        for index in route.legs.indices {
            await findLeg(index)
        }
    }

    private func findLeg(_ index: Int) async {
        guard route.legs.indices.contains(index), let start = route.legs[index].first,
            let end = route.legs[index].last
        else { return }
        isRouting = true
        defer { isRouting = false }
        do {
            let path =
                followsPaths
                ? try await router.path(from: start, to: end)
                : StraightRouter().path(from: start, to: end)
            // The route may have changed while the path was being found.
            guard route.legs.indices.contains(index), route.legs[index].first == start,
                route.legs[index].last == end
            else { return }
            route.legs[index] = path
            problem = nil
        } catch {
            guard !(error is CancellationError) else { return }
            // Without a path, the leg stays straight.
            problem = Problem(error)
        }
    }
}
