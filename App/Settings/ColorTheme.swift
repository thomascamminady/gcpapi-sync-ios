import SwiftUI

/// The hues every color of the app is drawn from, so that the same thing has the same color
/// everywhere: one categorical palette plus a few neutral and sequential shades.
enum Hue: CaseIterable {
    case blue
    case orange
    case aqua
    case amber
    case magenta
    case green
    case violet
    case red
    case gray
    case brown
    case deepBlue
    case lightBlue
}

/// A set of colors for every hue. Individual colors can still be changed in the settings.
nonisolated enum ColorTheme: String, Codable, CaseIterable, Sendable {
    /// Checked for color-vision deficiencies in light and dark mode.
    case balanced
    /// Apple's system colors.
    case vivid
    /// Muted pastels.
    case soft

    var title: String {
        switch self {
        case .balanced: String(localized: "Balanced")
        case .vivid: String(localized: "Vivid")
        case .soft: String(localized: "Soft")
        }
    }

    @MainActor func color(_ hue: Hue) -> Color {
        switch self {
        case .balanced: Self.balanced(hue)
        case .vivid: Self.vivid(hue)
        case .soft: Self.soft(hue)
        }
    }

    @MainActor private static func balanced(_ hue: Hue) -> Color {
        switch hue {
        case .blue: Color(light: 0x2A78D6, dark: 0x3987E5)
        case .orange: Color(light: 0xEB6834, dark: 0xD95926)
        case .aqua: Color(light: 0x1BAF7A, dark: 0x199E70)
        case .amber: Color(light: 0xEDA100, dark: 0xC98500)
        case .magenta: Color(light: 0xE87BA4, dark: 0xD55181)
        case .green: Color(light: 0x2E9E3E, dark: 0x3FB54F)
        case .violet: Color(light: 0x6250D6, dark: 0x9085E9)
        case .red: Color(light: 0xE34948, dark: 0xE66767)
        case .gray: Color(light: 0x8E8E93, dark: 0x8E8E93)
        case .brown: Color(light: 0x9A7B5C, dark: 0xB4936F)
        case .deepBlue: Color(light: 0x1F4E9C, dark: 0x5B7FE0)
        case .lightBlue: Color(light: 0x6DA7EC, dark: 0x86B6EF)
        }
    }

    @MainActor private static func vivid(_ hue: Hue) -> Color {
        switch hue {
        case .blue: .blue
        case .orange: .orange
        case .aqua: .mint
        case .amber: .yellow
        case .magenta: .pink
        case .green: .green
        case .violet: .purple
        case .red: .red
        case .gray: .gray
        case .brown: .brown
        case .deepBlue: .indigo
        case .lightBlue: .cyan
        }
    }

    @MainActor private static func soft(_ hue: Hue) -> Color {
        switch hue {
        case .blue: Color(light: 0x7AA7E0, dark: 0x6F9AD6)
        case .orange: Color(light: 0xF0A27A, dark: 0xE0906A)
        case .aqua: Color(light: 0x7CC9AE, dark: 0x6AB89D)
        case .amber: Color(light: 0xF2C66B, dark: 0xDDB25C)
        case .magenta: Color(light: 0xEFA6C3, dark: 0xDB92B0)
        case .green: Color(light: 0x8CC084, dark: 0x7AB073)
        case .violet: Color(light: 0xA99AE6, dark: 0x9B8CDB)
        case .red: Color(light: 0xEE8F8F, dark: 0xE07E7E)
        case .gray: Color(light: 0xA8A8AD, dark: 0x8E8E93)
        case .brown: Color(light: 0xC2A68A, dark: 0xAE9378)
        case .deepBlue: Color(light: 0x6E86C9, dark: 0x6F86CC)
        case .lightBlue: Color(light: 0xA9C8F0, dark: 0x9DBDE8)
        }
    }
}
