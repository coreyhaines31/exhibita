import AppKit
import ExhibitEditor
import ExhibitShell

/// Routes keys to the editor first. Only keys the editor ignores reach AppKit.
final class EditorWindow: NSWindow {
    weak var editor: CaptureEditor?
    weak var dictation: DictationSession?
    var onAppCommand: (EditorCommand) -> Void = { _ in }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func keyDown(with event: NSEvent) {
        if !route(event) { super.keyDown(with: event) }
    }

    /// The dictate key (D unless changed) coming up stops listening.
    override func keyUp(with event: NSEvent) {
        if let key = EditorKey(event), editor?.keymap.releasesDictation(key) == true { dictation?.release() }
        super.keyUp(with: event)
    }

    /// ⌘ keys arrive here before `keyDown`; the editor's take precedence over the (absent) menus.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.type == .keyDown, event.modifierFlags.contains(.command), route(event) { return true }
        return super.performKeyEquivalent(with: event)
    }

    private func route(_ event: NSEvent) -> Bool {
        guard let editor, let key = EditorKey(event) else { return false }
        // Esc while listening cancels dictation instead of closing.
        if let dictation, dictation.intercept(key) { return true }
        let modifiers = KeyModifiers(event)
        let typed: EditorKey
        // Labels take what was typed, shifted letters and all; tool keys read the unmodified key.
        if editor.editingTextID != nil, case .character = key, let characters = event.characters, !characters.isEmpty,
           modifiers.isSubset(of: [.shift]) {
            typed = .character(characters)
        } else {
            typed = key
        }
        switch editor.handle(typed, modifiers: modifiers) {
        case .handled: return true
        case .app(.dictate):
            // Held keys repeat; only the first press starts listening.
            if !event.isARepeat { dictation?.press() }
            return true
        case .app(.typeInstruction):
            dictation?.beginTyping()
            return true
        case .app(let command):
            onAppCommand(command)
            return true
        case .ignored: return false
        }
    }
}
