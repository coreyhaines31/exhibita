import AppKit
import ExhibitShell
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// No library default: `HotkeyCenter` writes the key in effect, so it follows the takeover state.
    static let captureAndEdit = Self("captureAndEdit")
    static let captureToClipboard = Self("captureToClipboard")
}

extension HotkeyAction {
    var shortcutName: KeyboardShortcuts.Name {
        switch self {
        case .captureAndEdit: .captureAndEdit
        case .captureToClipboard: .captureToClipboard
        }
    }
}

extension KeyCombo {
    init(_ shortcut: KeyboardShortcuts.Shortcut) {
        self.init(keyCode: UInt16(clamping: shortcut.carbonKeyCode),
                  modifiers: KeyModifiers(rawValue: shortcut.modifiers.rawValue))
    }

    var shortcut: KeyboardShortcuts.Shortcut {
        KeyboardShortcuts.Shortcut(KeyboardShortcuts.Key(rawValue: Int(keyCode)),
                                   modifiers: NSEvent.ModifierFlags(rawValue: modifiers.rawValue))
    }
}
