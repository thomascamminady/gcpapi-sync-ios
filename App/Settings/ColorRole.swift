import SwiftUI

/// Everything the app colors, each configurable in the settings.
enum ColorRole: Hashable, Identifiable {
    case accent
    case metric(Metric)
    case sleepStage(SleepStage)
    case stress(StressLevel)
    case status(Status)
    case sport(Sport)
    /// Heart rate and power zones, 0 (zone 1) to 6 (zone 7).
    case zone(Int)
    case fitness
    case fatigue
    case form(FormZone)
    case measure(TrackMeasure)

    /// Garmin's stress bands.
    enum StressLevel: String, CaseIterable {
        case rest
        case low
        case medium
        case high
    }

    /// Good, fair and poor, as for Garmin's HRV status.
    enum Status: String, CaseIterable {
        case good
        case fair
        case poor
    }

    /// The groups the settings list colors in.
    enum Group: String, CaseIterable, Identifiable {
        case app
        case health
        case sleep
        case stress
        case status
        case sports
        case zones
        case training
        case activity

        var id: Self { self }

        var title: String {
            switch self {
            case .app: String(localized: "App")
            case .health: String(localized: "Health Metrics")
            case .sleep: String(localized: "Sleep Stages")
            case .stress: String(localized: "Stress Levels")
            case .status: String(localized: "Status")
            case .sports: String(localized: "Sports")
            case .zones: String(localized: "Heart Rate and Power Zones")
            case .training: String(localized: "Training Load and Form")
            case .activity: String(localized: "Activity Charts")
            }
        }

        var roles: [ColorRole] {
            switch self {
            case .app: [.accent]
            case .health: Metric.allCases.map(ColorRole.metric)
            case .sleep: SleepStage.allCases.map(ColorRole.sleepStage)
            case .stress: StressLevel.allCases.map(ColorRole.stress)
            case .status: Status.allCases.map(ColorRole.status)
            case .sports: Sport.allCases.map(ColorRole.sport)
            case .zones: (0..<7).map(ColorRole.zone)
            case .training: [.fitness, .fatigue] + FormZone.allCases.map(ColorRole.form)
            case .activity: TrackMeasure.allCases.map(ColorRole.measure)
            }
        }
    }

    var id: String { key }

    /// The key the user's color is saved under.
    var key: String {
        switch self {
        case .accent: "accent"
        case .metric(let metric): "metric.\(metric.rawValue)"
        case .sleepStage(let stage): "sleep.\(stage.rawValue)"
        case .stress(let level): "stress.\(level.rawValue)"
        case .status(let status): "status.\(status.rawValue)"
        case .sport(let sport): "sport.\(sport.rawValue)"
        case .zone(let zone): "zone.\(zone + 1)"
        case .fitness: "fitness"
        case .fatigue: "fatigue"
        case .form(let zone): "form.\(zone.rawValue)"
        case .measure(let measure): "measure.\(measure.rawValue)"
        }
    }

    var title: String {
        switch self {
        case .accent: String(localized: "Accent")
        case .metric(let metric): metric.title
        case .sleepStage(let stage): stage.label
        case .stress(let level): level.title
        case .status(let status): status.title
        case .sport(let sport): sport.title
        case .zone(let zone): String(localized: "Zone \(zone + 1)")
        case .fitness: String(localized: "Fitness")
        case .fatigue: String(localized: "Fatigue")
        case .form(let zone): zone.title
        case .measure(let measure): measure.title(for: .running)
        }
    }

    /// The color of the user's theme, unless it is the accent of the app icon.
    var defaultColor: Color {
        guard let hue else { return Color(.accent) }
        return Preferences.shared.settings.theme.color(hue)
    }

    /// The hue of the role in every theme: the same thing has the same color everywhere.
    var hue: Hue? {
        switch self {
        case .accent: nil
        case .metric(let metric): metric.hue
        case .sleepStage(let stage): stage.hue
        case .stress(let level): [.blue, .amber, .orange, .red][level.index]
        case .status(let status): [.green, .amber, .red][status.index]
        case .sport(let sport): sport.hue
        case .zone(let zone):
            [.gray, .blue, .green, .orange, .red, .violet, .magenta][min(zone, 6)]
        case .fitness: .blue
        case .fatigue: .orange
        case .form(let zone): zone.hue
        case .measure(let measure): measure.hue
        }
    }

    /// The color to draw with: the user's or the default.
    var color: Color {
        Preferences.shared.color(self)
    }
}

extension ColorRole.StressLevel {
    /// The level of an average stress from 0 to 100, by Garmin's bands.
    init(level: Int) {
        self =
            switch level {
            case ..<26: .rest
            case 26..<51: .low
            case 51..<76: .medium
            default: .high
            }
    }

    var title: String {
        switch self {
        case .rest: String(localized: "Resting")
        case .low: String(localized: "Low")
        case .medium: String(localized: "Medium")
        case .high: String(localized: "High")
        }
    }

    var index: Int {
        Self.allCases.firstIndex(of: self) ?? 0
    }
}

extension ColorRole.Status {
    var title: String {
        switch self {
        case .good: String(localized: "Good")
        case .fair: String(localized: "Fair")
        case .poor: String(localized: "Poor")
        }
    }

    var index: Int {
        Self.allCases.firstIndex(of: self) ?? 0
    }
}
