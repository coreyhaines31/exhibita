import CoreGraphics
import ExhibitShell
import PanelKit
import SwiftUI

/// One capture: thumbnail, where it came from, when and how big, "by agent" for agent captures. Selecting a row
/// shows its actions; Open or a double-click opens it in the editor.
struct HistoryRowView: View {
    let row: HistoryRow
    let thumbnail: CGImage?
    let actions: PanelActions
    let select: () -> Void

    @Environment(\.panelTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                ThumbnailView(image: thumbnail)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(row.title)
                            .font(PanelFont.body(13, .semibold))
                            .lineLimit(1)
                            .truncationMode(.tail)
                        if let tag = row.tag { Tag(text: tag) }
                    }
                    Text(row.subtitle)
                        .font(PanelFont.body(11.5).monospacedDigit())
                        .foregroundStyle(theme.sub)
                        .lineLimit(1)
                    if let expiry = row.expiry {
                        Text(expiry)
                            .font(PanelFont.body(11))
                            .foregroundStyle(theme.sub)
                    }
                }
                Spacer(minLength: 0)
            }
            if row.isSelected {
                HStack(spacing: 8) {
                    Button("Open") { actions.open(row.id) }
                        .buttonStyle(PanelButtonStyle(.primary, size: .compact))
                        .reportingFrame("open \(row.id)", to: actions)
                    Button("Copy") { actions.copy(row.id) }
                    Button("Show in Finder") { actions.reveal(row.id) }
                    Spacer()
                    Button("Delete") { actions.delete(row.id) }
                        .buttonStyle(PanelButtonStyle(.destructive, size: .compact))
                        .reportingFrame("delete \(row.id)", to: actions)
                }
                .buttonStyle(.panelCompact)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(row.isSelected ? theme.field : Color.clear)
        .contentShape(Rectangle())
        .reportingFrame("row \(row.id)", to: actions)
        .onTapGesture(count: 2) { actions.open(row.id) }
        .onTapGesture(perform: select)
        .accessibilityElement(children: .combine)
        .accessibilityLabel([row.title, row.tag, row.subtitle, row.expiry].compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(row.isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(named: "Open") { actions.open(row.id) }
    }
}

extension View {
    /// Tells `actions.reportFrame` where this view was laid out, for the end-to-end tests.
    func reportingFrame(_ name: String, to actions: PanelActions) -> some View {
        onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { actions.reportFrame(name, $0) }
    }
}

/// A capture's thumbnail on a small recessed plate, letterboxed to one shape so rows line up.
struct ThumbnailView: View {
    let image: CGImage?

    @Environment(\.panelTheme) private var theme

    static let size = CGSize(width: 64, height: 40)

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 3)
        ZStack {
            shape.fill(theme.track)
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                Image(systemName: "photo").foregroundStyle(theme.sub)
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .clipShape(shape)
        .overlay(shape.strokeBorder(theme.line, lineWidth: 1))
    }
}

/// "by agent": a small reversed label strip.
struct Tag: View {
    let text: String

    @Environment(\.panelTheme) private var theme

    var body: some View {
        Text(text.uppercased())
            .font(PanelFont.condensed(9.5, .semibold))
            .tracking(0.6)
            .foregroundStyle(theme.plateInk)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(theme.plate, in: RoundedRectangle(cornerRadius: 2))
            .fixedSize()
    }
}
