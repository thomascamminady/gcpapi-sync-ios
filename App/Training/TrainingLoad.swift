import Foundation
import GCPAPISync
import SwiftUI

/// Fitness, fatigue and form from Garmin's training load, as in the performance management
/// charts of TrainingPeaks and intervals.icu.
///
/// A day's load is the sum of its activities' training load. Fitness is its exponentially
/// weighted average over about six weeks (42 days), fatigue over about one week (7 days), and
/// form is fitness minus fatigue: negative while training builds fitness, positive when rested.
nonisolated enum TrainingLoad {
    static let fitnessDays = 42.0
    static let fatigueDays = 7.0

    struct Day: Identifiable, Hashable, Codable, Sendable {
        let date: GarminDate
        let load: Double
        let fitness: Double
        let fatigue: Double

        var id: GarminDate { date }
        var form: Double { fitness - fatigue }

        /// Form as a share of fitness, which the form zones are defined by.
        var formShare: Double? {
            fitness > 0 ? form / fitness : nil
        }

        var zone: FormZone? {
            formShare.map(FormZone.init(share:))
        }
    }

    /// One `Day` for each day from `first` through `last`, starting from zero fitness, with
    /// fitness and fatigue averaged over `fitnessDays` and `fatigueDays`.
    static func days(
        _ workouts: [Workout], from first: GarminDate, through last: GarminDate,
        fitnessDays: Double = fitnessDays, fatigueDays: Double = fatigueDays
    ) -> [Day] {
        var loads: [GarminDate: Double] = [:]
        for workout in workouts {
            loads[workout.date, default: 0] += workout.trainingLoad ?? 0
        }
        var fitness = 0.0
        var fatigue = 0.0
        return (0...max(0, first.days(to: last))).map { offset in
            let date = first.adding(days: offset)
            let load = loads[date] ?? 0
            fitness += (load - fitness) / fitnessDays
            fatigue += (load - fatigue) / fatigueDays
            return Day(date: date, load: load, fitness: fitness, fatigue: fatigue)
        }
    }
}

/// What form says about training, by form as a share of fitness (intervals.icu's zones).
nonisolated enum FormZone: String, CaseIterable, Sendable {
    case detraining
    case fresh
    case neutral
    case productive
    case overreaching

    init(share: Double) {
        self =
            switch share {
            case 0.2...: .detraining
            case 0.05..<0.2: .fresh
            case -0.1..<0.05: .neutral
            case -0.3 ..< -0.1: .productive
            default: .overreaching
            }
    }

    var title: String {
        switch self {
        case .detraining: String(localized: "Detraining")
        case .fresh: String(localized: "Fresh")
        case .neutral: String(localized: "Neutral")
        case .productive: String(localized: "Productive")
        case .overreaching: String(localized: "Overreaching")
        }
    }

    var symbol: String {
        switch self {
        case .detraining: "arrow.down.right"
        case .fresh: "sparkles"
        case .neutral: "equal"
        case .productive: "arrow.up.right"
        case .overreaching: "exclamationmark.triangle.fill"
        }
    }

    /// The zone's color, as the user chose it.
    @MainActor var color: Color { ColorRole.form(self).color }

    /// Like statuses: amber, blue, gray, green and red.
    var hue: Hue {
        switch self {
        case .detraining: .amber
        case .fresh: .blue
        case .neutral: .gray
        case .productive: .green
        case .overreaching: .red
        }
    }

    /// The zone's band of form as a share of fitness, for charts.
    var band: ClosedRange<Double> {
        switch self {
        case .detraining: 0.2...0.4
        case .fresh: 0.05...0.2
        case .neutral: -0.1...0.05
        case .productive: -0.3 ... -0.1
        case .overreaching: -0.5 ... -0.3
        }
    }

    var explanation: String {
        switch self {
        case .detraining:
            String(localized: "Much more rested than fit: fitness is fading.")
        case .fresh:
            String(localized: "Rested and ready for a race or a hard effort.")
        case .neutral:
            String(localized: "Training about as much as you are used to.")
        case .productive:
            String(localized: "Building fitness: more load than you are used to.")
        case .overreaching:
            String(localized: "Far more load than you are used to: plan rest.")
        }
    }
}
