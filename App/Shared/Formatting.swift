import Foundation
import SwiftUI

/// Text for the dashboard's numbers.
enum Format {
    /// `7h 32m`, or an en dash without a value.
    static func duration(seconds: Int?) -> String {
        guard let seconds else { return "–" }
        return Duration.seconds(seconds).formatted(
            .units(allowed: [.hours, .minutes], width: .narrow))
    }

    /// A localized number, or an en dash without a value.
    static func number(_ value: Int?) -> String {
        value?.formatted() ?? "–"
    }

    /// Garmin's HRV status as a label and a color.
    static func hrvStatus(_ status: String?) -> (label: String, color: Color)? {
        switch status {
        case "BALANCED": (String(localized: "Balanced"), .green)
        case "UNBALANCED": (String(localized: "Unbalanced"), .orange)
        case "LOW": (String(localized: "Low"), .orange)
        case "POOR": (String(localized: "Poor"), .red)
        default: nil
        }
    }

    /// The color of a stress level, following Garmin's bands.
    static func stressColor(_ level: Int) -> Color {
        switch level {
        case ..<26: .blue
        case 26..<51: .yellow
        case 51..<76: .orange
        default: .red
        }
    }

    /// The stress band's name.
    static func stressLabel(_ level: Int?) -> String {
        switch level {
        case .none: "–"
        case .some(..<26): String(localized: "Resting")
        case .some(26..<51): String(localized: "Low")
        case .some(51..<76): String(localized: "Medium")
        default: String(localized: "High")
        }
    }
}
