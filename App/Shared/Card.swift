import SwiftUI
import UIKit

extension View {
    /// The rounded, grouped background of dashboard cards; tighter in dense mode.
    func cardStyle() -> some View {
        modifier(CardStyle())
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
            .padding(isDense ? 12 : 20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color(uiColor: .secondarySystemGroupedBackground),
                in: .rect(cornerRadius: isDense ? 18 : 26))
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
