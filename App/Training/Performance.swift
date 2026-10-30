import Foundation

/// Race times and training paces from a VO2max, by the running formulas of Jack Daniels and
/// Jimmy Gilbert: the oxygen cost of a speed (``VO2maxEstimator/cost(metresPerMinute:)``), and
/// the share of VO2max a runner can hold for a given time.
nonisolated enum Performance {
    /// A race distance with its prediction.
    struct Prediction: Hashable, Sendable {
        let metres: Double
        /// The predicted time, in seconds.
        let seconds: Double

        var metresPerSecond: Double { metres / seconds }
    }

    /// A training intensity: a range of shares of VO2max and the paces they take.
    enum Intensity: String, CaseIterable, Identifiable, Sendable {
        case easy
        case marathon
        case threshold
        case interval
        case repetition

        var id: Self { self }

        /// The shares of VO2max the intensity runs at.
        var shares: ClosedRange<Double> {
            switch self {
            case .easy: 0.59...0.74
            case .marathon: 0.75...0.84
            case .threshold: 0.88...0.92
            case .interval: 0.95...1.00
            case .repetition: 1.05...1.10
            }
        }

        var title: String {
            switch self {
            case .easy: String(localized: "Easy")
            case .marathon: String(localized: "Marathon")
            case .threshold: String(localized: "Threshold")
            case .interval: String(localized: "Interval")
            case .repetition: String(localized: "Repetition")
            }
        }
    }

    /// The distances predictions are made for: 1 km to the marathon.
    static let raceDistances: [Double] = [1000, 3000, 5000, 10_000, 21_097.5, 42_195]

    /// The share of VO2max a runner can hold for `minutes`: about 1.0 for 10 minutes, 0.8 for
    /// a few hours.
    static func sustainableShare(minutes: Double) -> Double {
        0.8 + 0.1894393 * exp(-0.012778 * minutes) + 0.2989558 * exp(-0.1932605 * minutes)
    }

    /// The speed in metres per minute whose oxygen cost is `oxygen` ml/kg/min: the inverse of
    /// ``VO2maxEstimator/cost(metresPerMinute:)``, or `nil` for no positive speed.
    static func speed(oxygen: Double) -> Double? {
        // 0.000104 v² + 0.182258 v − (4.60 + oxygen) = 0
        let (a, b, c) = (0.000104, 0.182258, -(4.60 + oxygen))
        let speed = (-b + (b * b - 4 * a * c).squareRoot()) / (2 * a)
        return speed > 0 ? speed : nil
    }

    /// The time to run `metres` at the effort `vo2max` allows over that time, or `nil` without a
    /// usable VO2max (below 10 or above 100 ml/kg/min) or distance.
    static func raceTime(metres: Double, vo2max: Double) -> Double? {
        guard metres > 0, (10...100).contains(vo2max) else { return nil }
        // The oxygen a time needs, relative to what can be held for it, falls as the time grows:
        // find the time at which the two meet by bisection, in minutes.
        func excess(_ minutes: Double) -> Double {
            VO2maxEstimator.cost(metresPerMinute: metres / minutes)
                / sustainableShare(minutes: minutes) - vo2max
        }
        var fast = metres / 1000  // 1000 m a minute: no human is faster
        var slow = metres / 20  // 20 m a minute: slower than walking
        guard excess(fast) > 0, excess(slow) < 0 else { return nil }
        for _ in 0..<60 {
            let middle = (fast + slow) / 2
            if excess(middle) > 0 {
                fast = middle
            } else {
                slow = middle
            }
        }
        return (fast + slow) / 2 * 60
    }

    /// The predicted times of ``raceDistances``.
    static func predictions(vo2max: Double) -> [Prediction] {
        raceDistances.compactMap { metres in
            raceTime(metres: metres, vo2max: vo2max).map { Prediction(metres: metres, seconds: $0) }
        }
    }

    /// The speeds, in metres per second, from the slowest to the fastest of `intensity`.
    static func speeds(_ intensity: Intensity, vo2max: Double) -> ClosedRange<Double>? {
        guard vo2max > 0,
            let slow = speed(oxygen: vo2max * intensity.shares.lowerBound),
            let fast = speed(oxygen: vo2max * intensity.shares.upperBound)
        else { return nil }
        return slow / 60...fast / 60
    }
}
