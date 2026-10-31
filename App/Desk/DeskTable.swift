import SwiftUI
import UIKit

/// The building blocks of the dashboard's tables: rows of fixed-width columns, so that a whole
/// row can be one link, striped, and highlighted under the pointer.
enum DeskStyle {
    /// The tables' text: the Mac's body size, which is small there, or the iPad's subheadline.
    static var font: Font {
        UIDevice.current.userInterfaceIdiom == .mac ? .body : .subheadline
    }

    /// The size of the dashboard's controls: small on the Mac, as its own apps have them.
    static var controlSize: ControlSize {
        UIDevice.current.userInterfaceIdiom == .mac ? .small : .regular
    }

    /// A section title of the dashboard.
    static var title: Font {
        UIDevice.current.userInterfaceIdiom == .mac ? .title3.weight(.semibold) : .title3.bold()
    }
}

extension View {
    /// A table cell `width` wide, on one line.
    func cell(_ width: CGFloat, alignment: Alignment = .trailing) -> some View {
        lineLimit(1).frame(width: width, alignment: alignment)
    }

    /// The table cell that takes the width the others leave.
    func flexibleCell() -> some View {
        lineLimit(1).truncationMode(.tail).frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A table row: every other one striped, and highlighted under the pointer.
struct DeskRow<Content: View>: View {
    let index: Int
    @ViewBuilder let content: Content
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            content
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(background, in: .rect(cornerRadius: 6))
        .contentShape(.rect)
        .onHover { isHovered = $0 }
    }

    private var background: Color {
        if isHovered {
            return Color.accentColor.opacity(0.12)
        }
        return index.isMultiple(of: 2) ? .clear : Color.primary.opacity(0.04)
    }
}

/// A table's header row, in the columns of its rows.
struct DeskHeader<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 8) {
            content
        }
        .font(DeskStyle.font.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.bottom, 4)
    }
}

/// A horizontal bar of `fraction` (0 to 1) of its width; from the middle when `isCentered`,
/// with `fraction` from −1 to 1.
struct MeterBar: View {
    let fraction: Double
    let color: Color
    var isCentered = false

    var body: some View {
        Canvas { context, size in
            let track = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 3)
            context.fill(track, with: .color(.primary.opacity(0.08)))
            let clamped = min(max(fraction, isCentered ? -1 : 0), 1)
            let width = size.width * abs(clamped) * (isCentered ? 0.5 : 1)
            let start = isCentered ? (clamped < 0 ? size.width / 2 - width : size.width / 2) : 0
            let bar = CGRect(x: start, y: 0, width: width, height: size.height)
            context.fill(Path(roundedRect: bar, cornerRadius: 3), with: .color(color))
            if isCentered {
                let middle = CGRect(
                    x: size.width / 2 - 0.5, y: -2, width: 1, height: size.height + 4)
                context.fill(Path(middle), with: .color(.secondary))
            }
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }
}

/// A titled group of the side panel.
struct PanelSection<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(DeskStyle.title)
                .accessibilityAddTraits(.isHeader)
            content
        }
    }
}

/// A row of the side panel: a label, an optional bar, and a value.
struct PanelRow<Bar: View>: View {
    let label: String
    let value: String
    var detail: String?
    @ViewBuilder let bar: Bar

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            bar
            HStack(spacing: 4) {
                Text(value)
                    .fontWeight(.medium)
                if let detail {
                    Text(detail)
                        .foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
            .monospacedDigit()
            // The figure keeps its width; the label gives way.
            .fixedSize()
        }
        .font(DeskStyle.font)
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }
}

extension PanelRow where Bar == EmptyView {
    init(label: String, value: String, detail: String? = nil) {
        self.init(label: label, value: value, detail: detail) { EmptyView() }
    }
}
