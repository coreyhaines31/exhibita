import Foundation

/// The two global hotkeys (spec, Keys).
public enum HotkeyAction: String, CaseIterable, Sendable, Codable, Identifiable {
    case captureAndEdit
    case captureToClipboard

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .captureAndEdit: "Capture and edit"
        case .captureToClipboard: "Capture to clipboard"
        }
    }

    public var detail: String {
        switch self {
        case .captureAndEdit: "Select, then mark it up."
        case .captureToClipboard: "Select, and the image is on the clipboard. No window opens."
        }
    }

    /// Before the system's screenshot shortcuts are turned off, Exhibit A uses ⌥ in place of ⌘ so the two never
    /// fight over a key. After takeover it uses the keys people already know.
    public func defaultCombo(takenOver: Bool) -> KeyCombo {
        let base: KeyModifiers = takenOver ? [.command, .shift] : [.option, .shift]
        switch self {
        case .captureAndEdit: return KeyCombo(keyCode: KeyCombo.digit4, modifiers: base)
        case .captureToClipboard: return KeyCombo(keyCode: KeyCombo.digit4, modifiers: base.union(.control))
        }
    }
}

/// Why a key can't be used for a hotkey.
public enum HotkeyIssue: Equatable, Sendable {
    /// Needs ⌘, ⌥ or ⌃; ⇧ alone would swallow ordinary typing.
    case needsModifier
    /// The other Exhibit A hotkey already uses it.
    case usedBy(HotkeyAction)
    /// One of macOS's screenshot shortcuts is on and uses it.
    case takenBySystem(SystemScreenshotShortcuts.Shortcut)

    public var message: String {
        switch self {
        case .needsModifier: "Add ⌘, ⌥ or ⌃ to this shortcut."
        case .usedBy(let action): "\(action.title) already uses this shortcut."
        case .takenBySystem(let shortcut):
            "macOS uses this for \"\(shortcut.title)\". Turn that off in Keyboard Shortcuts, Screenshots, or pick another."
        }
    }
}

/// The hotkeys in effect: a custom choice where the person made one, otherwise the default for the takeover
/// state. Custom choices are stored; defaults are not, so they move to ⇧⌘4 by themselves after takeover.
public struct HotkeyBindings: Equatable, Sendable {
    public var custom: [HotkeyAction: KeyCombo]
    public var system: SystemScreenshotShortcuts

    public init(custom: [HotkeyAction: KeyCombo] = [:], system: SystemScreenshotShortcuts = .factory) {
        self.custom = custom
        self.system = system
    }

    public var takenOver: Bool { system.selectionShortcutsAreOff }

    public func combo(for action: HotkeyAction) -> KeyCombo {
        custom[action] ?? action.defaultCombo(takenOver: takenOver)
    }

    public func isCustom(_ action: HotkeyAction) -> Bool { custom[action] != nil }

    /// Checks a key someone is about to assign to `action`.
    public func issue(assigning combo: KeyCombo, to action: HotkeyAction) -> HotkeyIssue? {
        if combo.modifiers.isDisjoint(with: [.command, .option, .control]) { return .needsModifier }
        for other in HotkeyAction.allCases where other != action && self.combo(for: other) == combo {
            return .usedBy(other)
        }
        if let shortcut = system.conflict(with: combo) { return .takenBySystem(shortcut) }
        return nil
    }

    /// The problem with a hotkey as things stand, for Settings to show beside it.
    public func issue(for action: HotkeyAction) -> HotkeyIssue? {
        issue(assigning: combo(for: action), to: action)
    }

    /// Assigns a key, or returns why not. Assigning the default clears the custom choice.
    public mutating func assign(_ combo: KeyCombo, to action: HotkeyAction) -> HotkeyIssue? {
        if let issue = issue(assigning: combo, to: action) { return issue }
        custom[action] = combo == action.defaultCombo(takenOver: takenOver) ? nil : combo
        return nil
    }

    public mutating func reset(_ action: HotkeyAction) {
        custom[action] = nil
    }

    /// Exchanges the two hotkeys' keys. Each side is stored only where it differs from that side's default, so
    /// swapping twice is back to nothing stored.
    public mutating func swap() {
        let edit = combo(for: .captureAndEdit)
        let clipboard = combo(for: .captureToClipboard)
        custom = [:]
        for (action, combo) in [(HotkeyAction.captureAndEdit, clipboard), (.captureToClipboard, edit)]
        where combo != action.defaultCombo(takenOver: takenOver) {
            custom[action] = combo
        }
    }

    /// What to suggest about the system shortcuts: nothing once they are off.
    public var takeoverSuggestion: TakeoverSuggestion {
        takenOver ? .done : .offer
    }

    public enum TakeoverSuggestion: Equatable, Sendable {
        /// Offer to link to Keyboard Shortcuts so ⇧⌘4 can move to Exhibit A.
        case offer
        case done
    }
}
