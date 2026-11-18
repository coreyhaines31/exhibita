import ExhibitShell
import KeyboardShortcuts

/// Registers the two global hotkeys. KeyboardShortcuts uses Carbon's `RegisterEventHotKey`, which needs no
/// Accessibility permission. The keys in effect are written here whenever the bindings change, so defaults
/// follow the takeover state and a refused recording snaps back.
@MainActor
final class HotkeyCenter {
    private let onHotkey: (HotkeyAction) -> Void

    init(onHotkey: @escaping (HotkeyAction) -> Void) {
        self.onHotkey = onHotkey
    }

    func install(_ bindings: HotkeyBindings) {
        apply(bindings)
        for action in HotkeyAction.allCases {
            KeyboardShortcuts.onKeyDown(for: action.shortcutName) { [weak self] in
                self?.onHotkey(action)
            }
        }
    }

    func apply(_ bindings: HotkeyBindings) {
        for action in HotkeyAction.allCases {
            let wanted = bindings.combo(for: action).shortcut
            if KeyboardShortcuts.getShortcut(for: action.shortcutName) != wanted {
                KeyboardShortcuts.setShortcut(wanted, for: action.shortcutName)
            }
        }
    }
}
