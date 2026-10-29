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
    var color: Color {
        switch self {
        case .running: Color(light: 0x2A78D6, dark: 0x3987E5)
        case .cycling: Color(light: 0xEB6834, dark: 0xD95926)
        case .swimming: Color(light: 0x1BAF7A, dark: 0x199E70)
        case .strength: Color(light: 0xEDA100, dark: 0xC98500)
        case .walking: Color(light: 0xE87BA4, dark: 0xD55181)
        case .other: Color(light: 0x008300, dark: 0x008300)
        }
    }
}
