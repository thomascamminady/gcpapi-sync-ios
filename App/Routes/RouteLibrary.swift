import Foundation
import Observation

/// The saved routes, newest first.
@Observable
final class RouteLibrary {
    private(set) var routes: [PlannedRoute]
    private(set) var problem: Problem?
    private let store: RouteStore?

    init(store: RouteStore?) {
        self.store = store
        routes = (store?.load() ?? []).sorted { $0.created > $1.created }
    }

    /// Add `route`, or replace the saved one with its id.
    func save(_ route: PlannedRoute) {
        if let index = routes.firstIndex(where: { $0.id == route.id }) {
            routes[index] = route
        } else {
            routes.insert(route, at: 0)
        }
        persist()
    }

    func delete(_ route: PlannedRoute) {
        routes.removeAll { $0.id == route.id }
        persist()
    }

    private func persist() {
        do {
            try store?.save(routes)
            problem = nil
        } catch {
            problem = Problem(error)
        }
    }
}
