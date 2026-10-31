import SwiftUI
import UIKit

extension Color {
    /// The background of every screen: plain white, or black in dark mode.
    static var page: Color { Color(uiColor: .systemBackground) }
}

extension View {
    /// A card on the page: outlined by a hairline, tighter in dense mode.
    func cardStyle() -> some View {
        modifier(CardStyle())
    }

    /// The page's color with a hairline around it, rounded by `cornerRadius`.
    func surface(cornerRadius: CGFloat = 14) -> some View {
        background(Color.page, in: .rect(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(Color(uiColor: .separator).opacity(0.6), lineWidth: 1)
            }
    }

    /// Lists and forms on the plain page instead of the grouped gray.
    func pageBackground() -> some View {
        scrollContentBackground(.hidden).background(Color.page)
    }

    /// Content no wider than reads well, centered on iPad and the Mac.
    func readableWidth(_ width: CGFloat = 820) -> some View {
        frame(maxWidth: width).frame(maxWidth: .infinity)
    }

    /// A chart's height, about two thirds of it in dense mode.
    func chartHeight(_ height: CGFloat) -> some View {
        modifier(ChartHeight(height: height))
    }
}

private struct CardStyle: ViewModifier {
    @Environment(\.isDense) private var isDense

    func body(content: Content) -> some View {
        content
            .padding(isDense ? 10 : 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .surface(cornerRadius: isDense ? 10 : 14)
    }
}

private struct ChartHeight: ViewModifier {
    let height: CGFloat
    @Environment(\.isDense) private var isDense

    func body(content: Content) -> some View {
        content.frame(height: isDense ? (height * 0.65).rounded() : height)
    }
}

/// A card's title, and a chevron when the card opens a detail screen.
struct CardHeader: View {
    let title: LocalizedStringKey
    let symbol: String
    let tint: Color
    var opensDetail = false

    var body: some View {
        HStack {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
            Spacer()
            if opensDetail {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
    }
}
