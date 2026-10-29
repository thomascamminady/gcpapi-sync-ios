import SwiftUI
import UIKit

extension View {
    /// The rounded, grouped background of dashboard cards.
    func cardStyle() -> some View {
        padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 26))
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
