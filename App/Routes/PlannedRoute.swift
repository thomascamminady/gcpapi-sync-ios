import Foundation

/// A route the user planned: the points they placed and the path between them.
nonisolated struct PlannedRoute: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var name: String
    let created: Date
    /// When the route was last saved, which decides between the versions of two devices.
    var modified: Date
    /// The points the user placed, in order.
    var waypoints: [GeoPoint]
    /// The path from each waypoint to the next, along roads and paths or straight; one fewer
    /// than the waypoints.
    var legs: [[GeoPoint]]

    init(
        id: UUID = UUID(), name: String = "", created: Date = .now, modified: Date? = nil,
        waypoints: [GeoPoint] = [], legs: [[GeoPoint]] = []
    ) {
        self.id = id
        self.name = name
        self.created = created
        self.modified = modified ?? created
        self.waypoints = waypoints
        self.legs = legs
    }

    /// The whole path: the legs joined, or the only waypoint.
    var path: [GeoPoint] {
        let joined = legs.reduce(into: [GeoPoint]()) { path, leg in
            path += path.isEmpty ? leg : Array(leg.dropFirst())
        }
        return joined.isEmpty ? Array(waypoints.prefix(1)) : joined
    }

    /// Metres along the path.
    var distance: Double {
        Self.length(path)
    }

    /// Whether the route ends where it starts.
    var isLoop: Bool {
        guard waypoints.count > 2, let first = waypoints.first, let last = waypoints.last else {
            return false
        }
        return first.distance(to: last) < 30
    }

    /// Metres along `points`.
    static func length(_ points: [GeoPoint]) -> Double {
        zip(points, points.dropFirst()).reduce(0) { $0 + $1.0.distance(to: $1.1) }
    }

    /// The route as GPX, for importing as a course in Garmin Connect or other apps.
    /// The point halfway along leg `index`, by distance: where a new point between its ends
    /// is offered.
    func midpoint(ofLeg index: Int) -> GeoPoint? {
        guard legs.indices.contains(index) else { return nil }
        let leg = legs[index]
        let half = Self.length(leg) / 2
        var covered = 0.0
        for (point, next) in zip(leg, leg.dropFirst()) {
            let step = point.distance(to: next)
            if covered + step >= half, step > 0 {
                let share = (half - covered) / step
                return GeoPoint(
                    latitude: point.latitude + (next.latitude - point.latitude) * share,
                    longitude: point.longitude + (next.longitude - point.longitude) * share)
            }
            covered += step
        }
        return leg.first
    }

    /// The name, or `Planned Route` without one.
    var title: String {
        name.isEmpty ? String(localized: "Planned Route") : name
    }

    /// The route as a FIT course, timed at `speed` metres per second from `start`.
    func fitCourse(speed: Double, start: Date = .now) -> Data {
        FITWriter.course(name: title, points: path, speed: speed, start: start)
    }

    func gpx() -> String {
        let title = name.isEmpty ? String(localized: "Planned Route") : name
        var lines = [
            #"<?xml version="1.0" encoding="UTF-8"?>"#,
            #"<gpx version="1.1" creator="gcpapi-sync-ios" xmlns="http://www.topografix.com/GPX/1/1">"#,
            "<trk><name>\(Self.xml(title))</name><trkseg>",
        ]
        for point in path {
            let latitude = Exporter.number(point.latitude)
            let longitude = Exporter.number(point.longitude)
            lines.append(#"<trkpt lat="\#(latitude)" lon="\#(longitude)"/>"#)
        }
        lines += ["</trkseg></trk>", "</gpx>"]
        return lines.joined(separator: "\n") + "\n"
    }

    private static func xml(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(
            of: "<", with: "&lt;"
        )
        .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
}

/// How the path between two points is found.
protocol Router: Sendable {
    /// The points from `start` to `end`: from exactly those, or from where roads and paths
    /// pass them.
    func path(from start: GeoPoint, to end: GeoPoint) async throws -> [GeoPoint]
}

/// Straight lines between the points.
nonisolated struct StraightRouter: Router {
    func path(from start: GeoPoint, to end: GeoPoint) -> [GeoPoint] {
        [start, end]
    }
}

/// The routes the user saved, kept on the device (and in its backups: they cannot be fetched
/// again).
nonisolated struct RouteStore: Sendable {
    /// The routes and the ids of those deleted, with when.
    struct Saved: Codable, Sendable {
        var routes: [PlannedRoute] = []
        var deleted: [UUID: Date] = [:]
    }

    let file: URL

    static let standard = Self(
        file: URL.applicationSupportDirectory.appending(path: "PlannedRoutes.json"))

    func load() -> [PlannedRoute] {
        loadSaved().routes
    }

    /// The routes and deletions, also from files of earlier versions, which hold only routes.
    func loadSaved() -> Saved {
        guard let data = try? Data(contentsOf: file) else { return Saved() }
        if let saved = try? JSONDecoder().decode(Saved.self, from: data) {
            return saved
        }
        return Saved(routes: (try? JSONDecoder().decode([PlannedRoute].self, from: data)) ?? [])
    }

    func save(_ routes: [PlannedRoute], deleted: [UUID: Date] = [:]) throws {
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(Saved(routes: routes, deleted: deleted)).write(
            to: file, options: [.atomic, .completeFileProtection])
    }
}

extension PlannedRoute {
    /// Routes of earlier versions have no modification date: their creation stands in.
    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        created = try container.decode(Date.self, forKey: .created)
        modified = try container.decodeIfPresent(Date.self, forKey: .modified) ?? created
        waypoints = try container.decode([GeoPoint].self, forKey: .waypoints)
        legs = try container.decode([[GeoPoint]].self, forKey: .legs)
    }
}
