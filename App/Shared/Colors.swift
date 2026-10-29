import SwiftUI
import UIKit

extension Color {
    /// A color with its own shade for light and for dark mode, from 0xRRGGBB values.
    nonisolated init(light: UInt32, dark: UInt32) {
        func color(_ hex: UInt32) -> UIColor {
            UIColor(
                red: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        }
        self.init(
            uiColor: UIColor { traits in
                color(traits.userInterfaceStyle == .dark ? dark : light)
            })
    }
}
