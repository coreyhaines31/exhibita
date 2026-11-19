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
            HStack(spacing: 10) {
                Nameplate(Brand.name.uppercased(), isLit: true)
                    .fixedSize()
                Seam()
                HStack(spacing: 4) {
                    ForEach(EditorTool.toolbarOrder, id: \.self) { tool in
                        ToolKey(tool: tool, isOn: editor.tool == tool) { editor.choose(tool) }
                    }
                }
                Seam()
                HStack(spacing: 6) {
                    ForEach(MarkColor.allCases, id: \.self) { color in
                        ColorLight(color: color, isOn: editor.currentColor == color) { editor.choose(color) }
                    }
                }
                Seam()
                HStack(spacing: 4) {
                    DictateKey(isOn: dictation?.isHeld == true,
                               press: { dictation?.press() }, release: { dictation?.release() })
                    LegendKey(key: "/", title: "Type", isOn: dictation?.isTyping == true) { dictation?.beginTyping() }
                        .accessibilityLabel("Type an instruction, key /")
                        .help("Type what to change instead of saying it (/)")
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
            StatusStrip(status: editor.status, hint: hint, actions: actions, dictation: dictation)
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
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        LegendKey(key: tool.defaultKey, title: tool.title, isOn: isOn, action: action)
            .accessibilityLabel("\(tool.title), key \(tool.defaultKey)")
            .accessibilityAddTraits(isOn ? .isSelected : [])
            .help("\(tool.title) (\(tool.defaultKey))")
    }
}

/// A key as the toolbar draws it: the key large, what it does small. On, it is a reversed plate.
private struct LegendKey: View {
    let key: String
    let title: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            KeyFace(key: key, title: title, isOn: isOn)
        }
        .buttonStyle(.plain)
    }
}

/// D: held with the mouse as with the key. Lit while listening.
private struct DictateKey: View {
    let isOn: Bool
    let press: () -> Void
    let release: () -> Void

    var body: some View {
        KeyFace(key: "D", title: "Say", isOn: isOn)
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in if !isOn { press() } }
                .onEnded { _ in release() })
            .accessibilityLabel("Dictate: hold D and say what to change")
            .accessibilityAddTraits(.isButton)
            .help("Hold D and say what to change, like \u{201C}blur the emails\u{201D}")
    }
}

private struct KeyFace: View {
    let key: String
    let title: String
    let isOn: Bool

    @Environment(\.panelTheme) private var theme

    var body: some View {
        VStack(spacing: 1) {
            Text(key)
                .font(PanelFont.condensed(15, .bold))
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
                Text(color.defaultKey)
                    .font(PanelFont.condensed(10, .bold))
                    .foregroundStyle(theme.ink2)
            }
            .frame(width: 18, height: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(color.title), key \(color.defaultKey)")
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .help("\(color.title) (\(color.defaultKey))")
    }
}

/// The outlined strip under the keys: a light and the status on the left, the current tool's hint, and the
/// keys that finish on the right.
private struct StatusStrip: View {
    let status: EditorStatus
    let hint: String
    let actions: EditorActions
    var dictation: DictationSession?

    @Environment(\.panelTheme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(light)
                .frame(width: 6, height: 6)
                .shadow(color: light, radius: status == .none ? 0 : 2.5)
            if let dictation, dictation.isTyping {
                InstructionField(dictation: dictation)
            } else {
                message
            }
            Spacer(minLength: 8)
            if case .dictation(let said) = status, let link = said.link {
                // A message that asks for something takes the room of the less used finishing keys; ⌘S and ⇧⌘C
                // still work, and the keys come back with the next action.
                FinishKey(keys: "\u{2192}", title: link.title) { actions.openLink(link) }
                FinishKey(keys: "↩", title: "Copy", action: actions.copyAndClose)
            } else {
                FinishKey(keys: "↩", title: "Copy", action: actions.copyAndClose)
                FinishKey(keys: "⌘S", title: "Save", action: actions.save)
                FinishKey(keys: "⇧⌘C", title: "Path", action: actions.copyPath)
            }
            FinishKey(keys: "Esc", title: "Close", action: actions.close)
        }
        .padding(.horizontal, 7)
        .frame(height: 24)
        .overlay(Rectangle().strokeBorder(theme.stripOutline, lineWidth: 1))
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var message: some View {
        if case .dictation(let said) = status, let transcript = said.transcript {
            // The message matters more than the words heard, so a long transcript is clipped first.
            HStack(spacing: 5) {
                Text("\u{201C}\(Self.clipped(transcript, to: said.link == nil ? 60 : 28))\u{201D}")
                    .foregroundStyle(theme.ink2)
                    .fixedSize()
                Text(said.message)
                    .foregroundStyle(theme.ink)
                    .truncationMode(.tail)
                    .layoutPriority(1)
            }
            .font(PanelFont.body(11.5, .semibold))
            .lineLimit(1)
        } else {
            Text(status.text ?? hint)
                .font(PanelFont.body(11.5, status == .none ? .regular : .semibold))
                .foregroundStyle(status == .none ? theme.ink2 : theme.ink)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    /// Long transcripts keep their start and end: "hide anything th…the customer".
    static func clipped(_ text: String, to limit: Int) -> String {
        guard text.count > limit else { return text }
        let half = (limit - 1) / 2
        return text.prefix(half).trimmingCharacters(in: .whitespaces) + "\u{2026}"
            + text.suffix(half).trimmingCharacters(in: .whitespaces)
    }

    private var light: Color {
        switch status {
        case .none: Color(white: 0.55)
        case .readingText, .secrets: theme.caution
        case .notice: theme.go
        case .dictation(let said): dictationLight(said)
        }
    }

    /// Red while listening, like a recording light; amber while working or when something needs doing.
    private func dictationLight(_ said: DictationStatus) -> Color {
        switch said {
        case .listening: theme.stop
        case .applied, .partial: theme.go
        default: theme.caution
        }
    }
}

/// The typed-instruction field in the status strip: ↩ applies, Esc closes it.
private struct InstructionField: View {
    let dictation: DictationSession
    static let prompt = "Type what to change, like \u{201C}blur the emails\u{201D}. \u{21A9} applies, Esc closes."
    @State private var text = ""
    @FocusState private var focused: Bool

    @Environment(\.panelTheme) private var theme
    @Environment(\.panelSnapshot) private var isSnapshot

    var body: some View {
        if isSnapshot {
            // ImageRenderer can't draw an AppKit text field; renders show the empty field's prompt and a caret.
            HStack(spacing: 1) {
                Rectangle().fill(theme.ink).frame(width: 1.5, height: 13)
                Text(Self.prompt).foregroundStyle(theme.ink2).lineLimit(1)
            }
            .font(PanelFont.body(11.5, .semibold))
        } else {
            field
        }
    }

    private var field: some View {
        TextField("", text: $text, prompt: Text(Self.prompt).foregroundStyle(theme.ink2))
            .textFieldStyle(.plain)
            .font(PanelFont.body(11.5, .semibold))
            .foregroundStyle(theme.ink)
            .focused($focused)
            .onSubmit {
                dictation.submit(text)
                text = ""
            }
            .onExitCommand { dictation.endTyping() }
            .onAppear { focused = true }
            .accessibilityLabel("Instruction")
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
