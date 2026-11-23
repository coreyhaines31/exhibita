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
    var dictation: DictationSession?

    @Environment(\.panelTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Nameplate(Brand.name.uppercased(), isLit: true)
                    .fixedSize()
                Seam()
                HStack(spacing: 4) {
                    ForEach(EditorTool.toolbarOrder, id: \.self) { tool in
                        ToolKey(tool: tool, key: keys.display(for: .tool(tool)), isOn: editor.tool == tool) {
                            editor.choose(tool)
                        }
                    }
                }
                Seam()
                HStack(spacing: 4) {
                    ForEach(MarkColor.allCases, id: \.self) { color in
                        ColorLight(color: color, key: keys.display(for: .color(color)),
                                   isOn: editor.currentColor == color) { editor.choose(color) }
                    }
                }
                Seam()
                HStack(spacing: 4) {
                    let secrets = keys.display(for: .blurAllSensitive)
                    LegendKey(icon: .blurSecrets, key: secrets, title: "Secrets", isOn: false) {
                        editor.blurAllSensitive()
                    }
                    .accessibilityLabel("Blur secrets, key \(secrets)")
                    .help("Blur every email, key, card and phone number found (\(secrets))")
                    DictateKey(key: keys.display(for: .dictate), isOn: dictation?.isHeld == true,
                               press: { dictation?.press() }, release: { dictation?.release() })
                    let type = keys.display(for: .typeInstruction)
                    LegendKey(icon: .type, key: type, title: "Type", isOn: dictation?.isTyping == true) {
                        dictation?.beginTyping()
                    }
                    .accessibilityLabel("Type an instruction, key \(type)")
                    .help("Type what to change instead of saying it (\(type))")
                }
                Seam()
                HStack(spacing: 4) {
                    KeyCap("arrow.uturn.backward", accessibilityLabel: "Undo, ⌘Z") { editor.undo() }
                        .disabled(!editor.canUndo)
                    KeyCap("arrow.uturn.forward", accessibilityLabel: "Redo, ⇧⌘Z") { editor.redo() }
                        .disabled(!editor.canRedo)
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, leadingInset)
            StatusStrip(status: editor.status, keys: keys, hint: hint, actions: actions, dictation: dictation)
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 9)
        .frame(height: EditorLayout.toolbarHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BrushedMetal(anodised: theme.isDark))
        .overlay(alignment: .top) { Rectangle().fill(theme.fasciaHighlight).frame(height: 1) }
    }

    private var keys: EditorKeymap { editor.keymap }

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

/// A vertical rule between groups of keys, as tall as the keys. A drawn line rather than `Divider`, whose
/// AppKit-backed rule ignores its frame in a live window and runs the full height of the toolbar.
private struct Seam: View {
    @Environment(\.panelTheme) private var theme

    var body: some View {
        Rectangle().fill(theme.fasciaEdge).frame(width: 1, height: 26)
    }
}

/// One tool: its key large, its name small, on a metal key. The current tool's key is a reversed plate.
private struct ToolKey: View {
    let tool: EditorTool
    /// The key in effect, which may not be the default.
    let key: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        LegendKey(icon: .tool(tool), key: key, title: tool.title, isOn: isOn, action: action)
            .accessibilityLabel("\(tool.title), key \(key)")
            .accessibilityAddTraits(isOn ? .isSelected : [])
            .help("\(tool.title) (\(key))")
    }
}

/// A key as the toolbar draws it: its icon and key on top, what it does small beneath. On, it is a reversed plate.
private struct LegendKey: View {
    let icon: KeyIcon
    let key: String
    let title: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            KeyFace(icon: icon, key: key, title: title, isOn: isOn)
        }
        .buttonStyle(.plain)
    }
}

/// D: held with the mouse as with the key. Lit while listening.
private struct DictateKey: View {
    let key: String
    let isOn: Bool
    let press: () -> Void
    let release: () -> Void

    var body: some View {
        KeyFace(icon: .dictate, key: key, title: "Say", isOn: isOn)
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in if !isOn { press() } }
                .onEnded { _ in release() })
            .accessibilityLabel("Dictate: hold \(key) and say what to change")
            .accessibilityAddTraits(.isButton)
            .help("Hold \(key) and say what to change, like \u{201C}blur the emails\u{201D}")
    }
}

/// The icon is what you find at a glance; the key beside it is how you learn the keyboard. Both share the key's one
/// ink, and the plate reverses when the key is on.
private struct KeyFace: View {
    let icon: KeyIcon
    let key: String
    let title: String
    let isOn: Bool

    @Environment(\.panelTheme) private var theme

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 3) {
                KeyIconView(icon: icon)
                Text(key)
                    .font(PanelFont.condensed(14, .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            // A fixed row height, so a key that shrinks to fit (⇧B, ⌥⇧Q) keeps its caption level with the rest.
            .frame(maxWidth: 38, minHeight: 17, maxHeight: 17)
            Text(title.uppercased())
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
}

/// A colour as a pilot light with its key beneath. The colour in use is lit.
private struct ColorLight: View {
    let color: MarkColor
    let key: String
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
                Text(key)
                    .font(PanelFont.condensed(10, .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .foregroundStyle(theme.ink2)
            }
            .frame(width: 18, height: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(color.title), key \(key)")
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .help("\(color.title) (\(key))")
    }
}
