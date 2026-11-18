import ExhibitCore
import ExhibitEditor
import PanelKit
import SwiftUI

/// Brushed metal across the top: the nameplate, one key plate per tool with its key, the four colour lights,
/// undo and redo, then a status strip with what the last action did and the keys that finish.
struct EditorToolbar: View {
    let editor: CaptureEditor
    let actions: EditorActions
    let leadingInset: CGFloat

    @Environment(\.panelTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Nameplate(Brand.name.uppercased(), isLit: true)
                Divider().frame(height: 26).overlay(theme.fasciaEdge)
                HStack(spacing: 4) {
                    ForEach(EditorTool.toolbarOrder, id: \.self) { tool in
                        ToolKey(tool: tool, isOn: editor.tool == tool) { editor.choose(tool) }
                    }
                }
                Divider().frame(height: 26).overlay(theme.fasciaEdge)
                HStack(spacing: 6) {
                    ForEach(MarkColor.allCases, id: \.self) { color in
                        ColorLight(color: color, isOn: editor.currentColor == color) { editor.choose(color) }
                    }
                }
                Divider().frame(height: 26).overlay(theme.fasciaEdge)
                HStack(spacing: 4) {
                    KeyCap("arrow.uturn.backward", accessibilityLabel: "Undo, ⌘Z") { editor.undo() }
                        .disabled(!editor.canUndo)
                    KeyCap("arrow.uturn.forward", accessibilityLabel: "Redo, ⇧⌘Z") { editor.redo() }
                        .disabled(!editor.canRedo)
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, leadingInset)
            StatusStrip(status: editor.status, hint: hint, actions: actions)
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 9)
        .frame(height: EditorLayout.toolbarHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BrushedMetal(anodised: theme.isDark))
        .overlay(alignment: .top) { Rectangle().fill(theme.fasciaHighlight).frame(height: 1) }
    }

    /// What the current tool does, in a few words.
    private var hint: String {
        switch editor.tool {
        case .select: "Drag a mark to move it. ⌫ deletes."
        case .arrow: "Drag from where to what; it snaps to text."
        case .circle: "Click text to circle it, or drag."
        case .blur: "Click a line or a secret to blur it, or drag."
        case .highlight: "Click a line to highlight it, or drag."
        case .text: "Click, type, then ↩."
        case .box: "Click text to box it, or drag."
        case .step: "Click to place step \(editor.nextStepNumber)."
        }
    }
}

/// One tool: its key large, its name small, on a metal key. The current tool's key is a reversed plate.
private struct ToolKey: View {
    let tool: EditorTool
    let isOn: Bool
    let action: () -> Void

    @Environment(\.panelTheme) private var theme

    var body: some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Text(tool.key)
                    .font(PanelFont.condensed(15, .bold))
                Text(tool.title.uppercased())
                    .font(PanelFont.condensed(8, .semibold))
                    .tracking(0.4)
                    .lineLimit(1)
                    .fixedSize()
            }
            .frame(width: 42, height: 34)
            .foregroundStyle(isOn ? theme.plateInk : (theme.isDark ? theme.ink : Color(white: 0.17)))
            .background {
                let shape = RoundedRectangle(cornerRadius: 4)
                if isOn {
                    shape.fill(theme.plate)
                } else if theme.isDark {
                    shape.fill(LinearGradient(colors: theme.button2, startPoint: .top, endPoint: .bottom))
                        .overlay(shape.strokeBorder(theme.button2Edge, lineWidth: 1))
                } else {
                    shape.fill(.white.opacity(0.45))
                        .overlay(shape.strokeBorder(.black.opacity(0.15), lineWidth: 1))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(tool.title), key \(tool.key)")
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .help("\(tool.title) (\(tool.key))")
    }
}

/// A colour as a pilot light with its key beneath. The colour in use is lit.
private struct ColorLight: View {
    let color: MarkColor
    let isOn: Bool
    let action: () -> Void

    @Environment(\.panelTheme) private var theme

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Circle()
                    .fill(color.swatch.opacity(isOn ? 1 : 0.3))
                    .frame(width: 9, height: 9)
                    .shadow(color: isOn ? color.swatch : .clear, radius: 3)
                    .overlay(Circle().strokeBorder(.black.opacity(isOn ? 0.25 : 0.15), lineWidth: 0.5))
                Text(color.key)
                    .font(PanelFont.condensed(10, .bold))
                    .foregroundStyle(theme.ink2)
            }
            .frame(width: 18, height: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(color.title), key \(color.key)")
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .help("\(color.title) (\(color.key))")
    }
}

/// The outlined strip under the keys: a light and the status on the left, the current tool's hint, and the
/// keys that finish on the right.
private struct StatusStrip: View {
    let status: EditorStatus
    let hint: String
    let actions: EditorActions

    @Environment(\.panelTheme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(light)
                .frame(width: 6, height: 6)
                .shadow(color: light, radius: status == .none ? 0 : 2.5)
            Text(status.text ?? hint)
                .font(PanelFont.body(11.5, status == .none ? .regular : .semibold))
                .foregroundStyle(status == .none ? theme.ink2 : theme.ink)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            FinishKey(keys: "↩", title: "Copy", action: actions.copyAndClose)
            FinishKey(keys: "⌘S", title: "Save", action: actions.save)
            FinishKey(keys: "⇧⌘C", title: "Path", action: actions.copyPath)
            FinishKey(keys: "Esc", title: "Close", action: actions.close)
        }
        .padding(.horizontal, 7)
        .frame(height: 24)
        .overlay(Rectangle().strokeBorder(theme.stripOutline, lineWidth: 1))
        .accessibilityElement(children: .contain)
    }

    private var light: Color {
        switch status {
        case .none: Color(white: 0.55)
        case .readingText, .secrets: theme.caution
        case .notice: theme.go
        }
    }
}

/// A finishing key in the status strip: the keys on a small plate, then what they do.
private struct FinishKey: View {
    let keys: String
    let title: String
    let action: () -> Void

    @Environment(\.panelTheme) private var theme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(keys)
                    .font(PanelFont.body(10, .bold))
                    .foregroundStyle(theme.plateInk)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(theme.plate, in: RoundedRectangle(cornerRadius: 2))
                Text(title.uppercased())
                    .font(PanelFont.condensed(9.5, .semibold))
                    .tracking(0.5)
                    .foregroundStyle(theme.ink2)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(keys)")
    }
}
