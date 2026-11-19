import AppKit
import ExhibitEditor
import ExhibitShell

extension EditorKey {
    /// A key event as the editor reads it: ↩, Esc and ⌫ by key code, everything else by the character typed
    /// without modifiers other than ⇧. The editor window and Settings' key recorder both read keys this way.
    init?(_ event: NSEvent) {
        if let special = EditorKey.special(keyCode: event.keyCode) {
            self = special
        } else if let typed = event.charactersIgnoringModifiers, !typed.isEmpty {
            self = .character(typed)
        } else {
            return nil
        }
    }
}

extension KeyModifiers {
    /// The modifiers held during a key event.
    init(_ event: NSEvent) {
        self = KeyModifiers(rawValue: event.modifierFlags.rawValue).intersection(.all)
    }
}
