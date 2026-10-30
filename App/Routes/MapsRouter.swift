import CoreLocation
import Foundation
import MapKit

/// Paths along roads and footpaths from Apple Maps' walking directions. Only the two points
/// of a leg are sent to Apple.
nonisolated struct MapsRouter: Router {
    func path(from start: GeoPoint, to end: GeoPoint) async throws -> [GeoPoint] {
        let request = MKDirections.Request()
        request.source = MKMapItem(
            location: CLLocation(latitude: start.latitude, longitude: start.longitude), address: nil
        )
        request.destination = MKMapItem(
            location: CLLocation(latitude: end.latitude, longitude: end.longitude), address: nil)
        request.transportType = .walking
        let response = try await MKDirections(request: request).calculate()
        guard let polyline = response.routes.first?.polyline, polyline.pointCount > 0 else {
            return [start, end]
        }
        var coordinates = [CLLocationCoordinate2D](
            repeating: kCLLocationCoordinate2DInvalid, count: polyline.pointCount)
        polyline.getCoordinates(
            &coordinates, range: NSRange(location: 0, length: polyline.pointCount))
        let points = coordinates.map { GeoPoint(latitude: $0.latitude, longitude: $0.longitude) }
        // The path begins and ends exactly where the user placed the points.
        return [start] + points + [end]
    }
}
