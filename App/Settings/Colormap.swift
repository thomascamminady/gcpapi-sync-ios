import SwiftUI

/// Perceptually uniform color maps, for coloring by value: equal steps of value look like
/// equal steps of color, the lightness rises steadily from one end to the other, and they read
/// in grayscale and for the common color-vision deficiencies alike. They are matplotlib's.
nonisolated enum Colormap: String, Codable, CaseIterable, Identifiable, Sendable {
    case viridis
    case cividis
    case plasma
    case inferno
    case magma

    var id: Self { self }

    /// The maps' names, which are the same in every language.
    var title: String {
        switch self {
        case .viridis: "Viridis"
        case .cividis: "Cividis"
        case .plasma: "Plasma"
        case .inferno: "Inferno"
        case .magma: "Magma"
        }
    }

    /// Colors at evenly spaced values from 0 to 1, sampled from matplotlib's tables.
    var stops: [UInt32] {
        switch self {
        case .viridis:
            [
                0x440154, 0x482475, 0x414487, 0x355F8D, 0x2A788E, 0x21918C, 0x22A884, 0x44BF70,
                0x7AD151, 0xBDDF26, 0xFDE725,
            ]
        case .cividis:
            [
                0x00204D, 0x00336F, 0x39486B, 0x575C6D, 0x707173, 0x8A8779, 0xA69D75, 0xC4B56C,
                0xE4CF5B, 0xFFEA46,
            ]
        case .plasma:
            [
                0x0D0887, 0x41049D, 0x6A00A8, 0x8F0DA4, 0xB12A90, 0xCC4778, 0xE16462, 0xF2844B,
                0xFCA636, 0xFCCE25, 0xF0F921,
            ]
        case .inferno:
            [
                0x000004, 0x160B39, 0x420A68, 0x6A176E, 0x932667, 0xBC3754, 0xDD513A, 0xF37819,
                0xFCA50A, 0xF6D746, 0xFCFFA4,
            ]
        case .magma:
            [
                0x000004, 0x140E36, 0x3B0F70, 0x641A80, 0x8C2981, 0xB73779, 0xDE4968, 0xF7705C,
                0xFE9F6D, 0xFECF92, 0xFCFDBF,
            ]
        }
    }

    /// The red, green and blue (0 to 1, in sRGB) at `value` from 0 to 1, clamped, interpolated
    /// in linear light between the neighbouring stops; from the other end when `isReversed`.
    func components(at value: Double, isReversed: Bool = false) -> (Double, Double, Double) {
        let clamped = value.isFinite ? min(max(value, 0), 1) : 0
        let position = (isReversed ? 1 - clamped : clamped) * Double(stops.count - 1)
        let lower = min(Int(position), stops.count - 2)
        let fraction = position - Double(lower)
        func channels(_ hex: UInt32) -> [Double] {
            [hex >> 16, hex >> 8, hex].map { Self.linear(Double($0 & 0xFF) / 255) }
        }
        let mixed = zip(channels(stops[lower]), channels(stops[lower + 1])).map { low, high in
            Self.gamma(low + (high - low) * fraction)
        }
        return (mixed[0], mixed[1], mixed[2])
    }

    /// The relative luminance (WCAG) at `value`: under about 0.18, white text reads better on
    /// it than black.
    func luminance(at value: Double, isReversed: Bool = false) -> Double {
        let (red, green, blue) = components(at: value, isReversed: isReversed)
        return 0.2126 * Self.linear(red) + 0.7152 * Self.linear(green) + 0.0722 * Self.linear(blue)
    }

    static func linear(_ channel: Double) -> Double {
        channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
    }

    static func gamma(_ channel: Double) -> Double {
        channel <= 0.0031308 ? channel * 12.92 : 1.055 * pow(channel, 1 / 2.4) - 0.055
    }
}

extension Colormap {
    /// The color at `value` from 0 to 1.
    func color(at value: Double, isReversed: Bool = false) -> Color {
        let (red, green, blue) = components(at: value, isReversed: isReversed)
        return Color(.sRGB, red: red, green: green, blue: blue)
    }

    /// Black or white, whichever reads better on the color at `value`.
    func textColor(at value: Double, isReversed: Bool = false) -> Color {
        luminance(at: value, isReversed: isReversed) < 0.18 ? .white : .black
    }

    /// The whole map from 0 to 1, left to right.
    func gradient(isReversed: Bool = false) -> LinearGradient {
        LinearGradient(
            stops: (0...20).map { step in
                let value = Double(step) / 20
                return .init(color: color(at: value, isReversed: isReversed), location: value)
            },
            startPoint: .leading, endPoint: .trailing)
    }
}

extension Preferences {
    /// The color map the user chose, at `value` from 0 to 1.
    func valueColor(_ value: Double) -> Color {
        settings.colormap.color(at: value, isReversed: settings.reversesColormap)
    }

    /// The text color that reads on ``valueColor(_:)``.
    func valueTextColor(_ value: Double) -> Color {
        settings.colormap.textColor(at: value, isReversed: settings.reversesColormap)
    }

    /// The chosen color map as a gradient.
    var valueGradient: LinearGradient {
        settings.colormap.gradient(isReversed: settings.reversesColormap)
    }
}
