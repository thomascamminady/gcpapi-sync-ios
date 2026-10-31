import Foundation
import Observation

/// The saved routes, newest first.
@Observable
final class RouteLibrary {
    private(set) var routes: [PlannedRoute]
    /// When each deleted route was deleted, for other devices to delete it too.
    private(set) var deleted: [UUID: Date]
    private(set) var problem: Problem?
    private let store: RouteStore?

    init(store: RouteStore?) {
        self.store = store
        let saved = store?.loadSaved() ?? RouteStore.Saved()
        routes = saved.routes.sorted { $0.created > $1.created }
        deleted = saved.deleted
    }

    /// Add `route`, or replace the saved one with its id, as changed now.
    func save(_ route: PlannedRoute) {
        var route = route
        route.modified = .now
        if let index = routes.firstIndex(where: { $0.id == route.id }) {
            routes[index] = route
        } else {
            routes.insert(route, at: 0)
        }
        persist()
    }

    func delete(_ route: PlannedRoute) {
        routes.removeAll { $0.id == route.id }
        deleted[route.id] = .now
        persist()
    }

    /// Take the routes and deletions a sync merged, if they differ.
    func adopt(_ routes: [PlannedRoute], deleted: [UUID: Date]) {
        let sorted = routes.sorted { $0.created > $1.created }
        guard sorted != self.routes || deleted != self.deleted else { return }
        self.routes = sorted
        self.deleted = deleted
        persist()
    }

    private func persist() {
        do {
            try store?.save(routes, deleted: deleted)
            problem = nil
        } catch {
            problem = Problem(error)
        }
    }
}
