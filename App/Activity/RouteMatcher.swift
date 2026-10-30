import Foundation

/// A place on Earth, in degrees.
nonisolated struct GeoPoint: Hashable, Codable, Sendable {
    let latitude: Double
    let longitude: Double

    /// Metres to `other` along the Earth's surface (haversine).
    func distance(to other: Self) -> Double {
        let radians = Double.pi / 180
        let dLatitude = (other.latitude - latitude) * radians
        let dLongitude = (other.longitude - longitude) * radians
        let a =
            sin(dLatitude / 2) * sin(dLatitude / 2)
            + cos(latitude * radians) * cos(other.latitude * radians)
            * sin(dLongitude / 2) * sin(dLongitude / 2)
        return 6_371_000 * 2 * atan2(a.squareRoot(), (1 - a).squareRoot())
    }
}

/// Finds activities on the same route as another.
///
/// Candidates come from what activity summaries tell: the same sport, a start and an end
/// nearby, and a similar distance. Their recorded routes then decide: two routes are the same
/// when, resampled at even spacing, every point of each lies close to the other, in whichever
/// direction they were run.
nonisolated enum RouteMatcher {
    /// How far apart starts and ends, and the routes' points on average, may be.
    static let tolerance = 250.0
    static let routeTolerance = 120.0
    /// How much the distances may differ, as a share.
    static let distanceShare = 0.1
    /// Points each route is resampled to.
    static let resolution = 64

    /// The activities that may be on `workout`'s route, the most alike first.
    static func candidates(for workout: Workout, in workouts: [Workout]) -> [Workout] {
        guard let start = workout.startPoint, let end = workout.endPoint,
            let distance = workout.distance
        else { return [] }
        return workouts.compactMap { other -> (workout: Workout, score: Double)? in
            guard other.id != workout.id, other.sport == workout.sport,
                let otherStart = other.startPoint, let otherEnd = other.endPoint,
                let otherDistance = other.distance,
                abs(otherDistance - distance) <= distance * distanceShare
            else { return nil }
            let startGap = start.distance(to: otherStart)
            let endGap = end.distance(to: otherEnd)
            guard startGap <= tolerance, endGap <= tolerance else { return nil }
            return (other, startGap + endGap + abs(otherDistance - distance))
        }
        .sorted { $0.score < $1.score }
        .map(\.workout)
    }

    /// `points` at `count` even steps along their length.
    static func resample(_ points: [GeoPoint], count: Int = resolution) -> [GeoPoint] {
        guard points.count > 1, count > 1 else { return points }
        var cumulative = [0.0]
        for (previous, next) in zip(points, points.dropFirst()) {
            cumulative.append((cumulative.last ?? 0) + previous.distance(to: next))
        }
        guard let total = cumulative.last, total > 0 else { return [points[0]] }
        var resampled: [GeoPoint] = []
        var segment = 0
        for step in 0..<count {
            let target = total * Double(step) / Double(count - 1)
            while segment < cumulative.count - 2, cumulative[segment + 1] < target {
                segment += 1
            }
            let span = cumulative[segment + 1] - cumulative[segment]
            let share = span > 0 ? (target - cumulative[segment]) / span : 0
            let start = points[segment]
            let end = points[segment + 1]
            resampled.append(
                GeoPoint(
                    latitude: start.latitude + share * (end.latitude - start.latitude),
                    longitude: start.longitude + share * (end.longitude - start.longitude)))
        }
        return resampled
    }

    /// The mean distance, in metres, from each point of either route to the nearest point
    /// of the other: 0 for the same route, in either direction.
    static func separation(_ first: [GeoPoint], _ second: [GeoPoint]) -> Double {
        let lhs = resample(first)
        let rhs = resample(second)
        guard !lhs.isEmpty, !rhs.isEmpty else { return .infinity }
        func meanNearest(_ points: [GeoPoint], _ others: [GeoPoint]) -> Double {
            points.reduce(0) { sum, point in
                sum + (others.map { point.distance(to: $0) }.min() ?? .infinity)
            } / Double(points.count)
        }
        return (meanNearest(lhs, rhs) + meanNearest(rhs, lhs)) / 2
    }

    /// Whether two recorded routes are the same route.
    static func isSameRoute(_ first: [GeoPoint], _ second: [GeoPoint]) -> Bool {
        separation(first, second) <= routeTolerance
    }
}
