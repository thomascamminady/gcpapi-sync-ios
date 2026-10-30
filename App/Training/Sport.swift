import SwiftUI

/// Groups of Garmin activity types, for icons, colors and weekly volume.
nonisolated enum Sport: String, CaseIterable, Identifiable, Sendable {
    case running
    case cycling
    case swimming
    case strength
    case walking
    case other

    var id: Self { self }

    /// The group of a Garmin activity type key such as `trail_running` or `road_biking`.
    init(typeKey: String?) {
        let key = typeKey ?? ""
        self =
            if key.contains("run") {
                .running
            } else if key.contains("cycl") || key.contains("bik") || key.contains("ride") {
                .cycling
            } else if key.contains("swim") {
                .swimming
            } else if key.contains("strength") {
                .strength
            } else if key.contains("walk") || key.contains("hik") {
                .walking
            } else {
                .other
            }
    }

    var title: String {
        switch self {
        case .running: String(localized: "Running")
        case .cycling: String(localized: "Cycling")
        case .swimming: String(localized: "Swimming")
        case .strength: String(localized: "Strength")
        case .walking: String(localized: "Walking & Hiking")
        case .other: String(localized: "Other")
        }
    }

    var symbol: String {
        switch self {
        case .running: "figure.run"
        case .cycling: "figure.outdoor.cycle"
        case .swimming: "figure.pool.swim"
        case .strength: "figure.strengthtraining.traditional"
        case .walking: "figure.hiking"
        case .other: "figure.mixed.cardio"
        }
    }

    /// Colors checked in this order for color-vision deficiencies, in light and dark mode.
    /// The sport's color, as the user chose it.
    @MainActor var color: Color { ColorRole.sport(self).color }

    /// The sport's hue in every color theme, in the order checked for stacked bars.
    var hue: Hue {
        switch self {
        case .running: .blue
        case .cycling: .orange
        case .swimming: .aqua
        case .strength: .amber
        case .walking: .magenta
        case .other: .green
        }
    }
}
