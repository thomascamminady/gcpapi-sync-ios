import Foundation

/// What a user's devices share through a folder they all chose: the planned routes and the
/// settings. Garmin's data needs no syncing: each device fetches it from Garmin.
nonisolated struct SharedState: Codable, Equatable, Sendable {
    var routes: [PlannedRoute] = []
    /// When each deleted route was deleted, by id, so that other devices delete it too.
    var deletedRoutes: [UUID: Date] = [:]
    var settings: Settings?
    /// When the settings last changed on any device.
    var settingsModified: Date?

    /// The newer of each route and of the settings in `self` and `other`: every route either
    /// has, changed last, without those deleted since; a route changed after its deletion is
    /// back.
    func merged(with other: Self) -> Self {
        var deleted = deletedRoutes.merging(other.deletedRoutes, uniquingKeysWith: max)
        var byID: [UUID: PlannedRoute] = [:]
        for route in routes + other.routes
        where byID[route.id].map({ $0.modified < route.modified }) ?? true {
            byID[route.id] = route
        }
        let kept = byID.values.filter { route in
            deleted[route.id].map { $0 < route.modified } ?? true
        }
        for route in kept {
            deleted[route.id] = nil
        }
        let newer =
            (other.settingsModified ?? .distantPast) > (settingsModified ?? .distantPast)
            ? other : self
        return Self(
            routes: kept.sorted { ($0.created, $0.id.uuidString) > ($1.created, $1.id.uuidString) },
            deletedRoutes: deleted, settings: newer.settings,
            settingsModified: newer.settingsModified)
    }
}
