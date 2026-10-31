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

    /// Move the point at `index` to `point`, and find the paths to and from it again.
    func move(at index: Int, to point: GeoPoint) async {
        guard route.waypoints.indices.contains(index) else { return }
        route.waypoints[index] = point
        if index > 0 {
            route.legs[index - 1] = [route.waypoints[index - 1], point]
        }
        if index < route.legs.count {
            route.legs[index] = [point, route.waypoints[index + 1]]
        }
        if index > 0 {
            await findLeg(index - 1)
        }
        await findLeg(index)
    }

    /// Add `point` between the points at `index` − 1 and `index`, and find the paths to and
    /// from it; at the end for any other `index`.
    func insert(_ point: GeoPoint, at index: Int) async {
        guard index > 0, index < route.waypoints.count, route.legs.indices.contains(index - 1)
        else {
            await add(point)
            return
        }
        route.waypoints.insert(point, at: index)
        route.legs.replaceSubrange(
            (index - 1)...(index - 1),
            with: [[route.waypoints[index - 1], point], [point, route.waypoints[index + 1]]])
        await findLeg(index - 1)
        await findLeg(index)
    }

    /// Remove the point at `index`, joining its neighbours by a path of their own.
    func remove(at index: Int) async {
        guard route.waypoints.indices.contains(index) else { return }
        route.waypoints.remove(at: index)
        guard !route.legs.isEmpty else { return }
        if index == 0 {
            route.legs.removeFirst()
        } else if index >= route.legs.count {
            route.legs.removeLast()
        } else {
            route.legs.replaceSubrange(
                (index - 1)...index,
                with: [[route.waypoints[index - 1], route.waypoints[index]]])
            await findLeg(index - 1)
        }
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

    /// Moves the points at the ends of leg `index` to where its path begins and ends (on a road,
    /// with directions), and the neighbouring legs' ends with them.
    private func snap(leg index: Int) {
        guard let first = route.legs[index].first, let last = route.legs[index].last else {
            return
        }
        route.waypoints[index] = first
        route.waypoints[index + 1] = last
        if index > 0, !route.legs[index - 1].isEmpty {
            route.legs[index - 1][route.legs[index - 1].count - 1] = first
        }
        if index + 1 < route.legs.count, !route.legs[index + 1].isEmpty {
            route.legs[index + 1][0] = last
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
            snap(leg: index)
            problem = nil
        } catch {
            guard !(error is CancellationError) else { return }
            // Without a path, the leg stays straight.
            problem = Problem(error)
        }
    }
}
