import ExhibitEditor
import PanelKit
import SwiftUI

/// The outlined strip under the keys: a light and the status on the left, the current tool's hint, and the
/// keys that finish on the right.
struct StatusStrip: View {
    let status: EditorStatus
    let keys: EditorKeymap
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
                FinishKey(keys: keys.display(for: .copyAndClose), icon: "doc.on.doc", title: "Copy",
                          action: actions.copyAndClose)
            } else {
                FinishKey(keys: keys.display(for: .copyAndClose), icon: "doc.on.doc", title: "Copy",
                          action: actions.copyAndClose)
                FinishKey(keys: keys.display(for: .save), icon: "square.and.arrow.down", title: "Save",
                          action: actions.save)
                FinishKey(keys: keys.display(for: .copyPath), icon: "link", title: "Path", action: actions.copyPath)
            }
            FinishKey(keys: keys.display(for: .close), icon: "xmark", title: "Close", action: actions.close)
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
                Text(said.message(keys: keys))
                    .foregroundStyle(theme.ink)
                    .truncationMode(.tail)
                    .layoutPriority(1)
            }
            .font(PanelFont.body(11.5, .semibold))
            .lineLimit(1)
        } else {
            Text(status.text(keys: keys) ?? hint)
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

/// A finishing key in the status strip: the keys on a small plate, then an icon and what they do.
private struct FinishKey: View {
    let keys: String
    var icon: String?
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
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(theme.ink2)
                }
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
