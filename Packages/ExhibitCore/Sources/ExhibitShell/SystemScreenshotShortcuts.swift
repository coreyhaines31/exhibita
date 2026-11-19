import Foundation

/// macOS's own screenshot shortcuts, read from the `AppleSymbolicHotKeys` dictionary in the
/// `com.apple.symbolichotkeys` preferences domain. Reading only: see `docs/product/hotkey-takeover.md` for why
/// Exhibit A does not write that domain.
public struct SystemScreenshotShortcuts: Sendable, Equatable {
    /// The symbolic hot key ids macOS uses for screenshots.
    public enum Shortcut: Int, CaseIterable, Sendable {
        case saveScreen = 28
        case copyScreen = 29
        case saveSelection = 30
        case copySelection = 31
        case options = 184

        /// The name System Settings shows.
        public var title: String {
            switch self {
            case .saveScreen: "Save picture of screen as a file"
            case .copyScreen: "Copy picture of screen to the clipboard"
            case .saveSelection: "Save picture of selected area as a file"
            case .copySelection: "Copy picture of selected area to the clipboard"
            case .options: "Screenshot and recording options"
            }
        }

        /// The factory setting, used when the preferences hold no entry.
        public var factoryCombo: KeyCombo {
            switch self {
            case .saveScreen: KeyCombo(keyCode: KeyCombo.digit3, modifiers: [.command, .shift])
            case .copyScreen: KeyCombo(keyCode: KeyCombo.digit3, modifiers: [.control, .command, .shift])
            case .saveSelection: KeyCombo(keyCode: KeyCombo.digit4, modifiers: [.command, .shift])
            case .copySelection: KeyCombo(keyCode: KeyCombo.digit4, modifiers: [.control, .command, .shift])
            case .options: KeyCombo(keyCode: KeyCombo.digit5, modifiers: [.command, .shift])
            }
        }
    }

    public struct Entry: Sendable, Equatable {
        public var shortcut: Shortcut
        public var isEnabled: Bool
        public var combo: KeyCombo
    }

    public var entries: [Entry]
    /// False when the preferences could not be read at all; every shortcut is then assumed on.
    public var wasRead: Bool

    /// Every shortcut on, at its factory keys: a Mac nobody has changed.
    public static let factory = SystemScreenshotShortcuts(
        entries: Shortcut.allCases.map { Entry(shortcut: $0, isEnabled: true, combo: $0.factoryCombo) },
        wasRead: false
    )

    public init(entries: [Entry], wasRead: Bool) {
        self.entries = entries
        self.wasRead = wasRead
    }

    /// Parses the `AppleSymbolicHotKeys` value. Each entry looks like
    /// `"30": {enabled: 1, value: {parameters: (52, 21, 1179648), type: standard}}`: the character, the virtual
    /// key code and the modifier mask. A missing entry means the factory setting, which is on.
    public init(symbolicHotKeys: Any?) {
        guard let table = symbolicHotKeys as? [String: Any] else {
            self = .factory
            return
        }
        entries = Shortcut.allCases.map { shortcut in
            guard let entry = table[String(shortcut.rawValue)] as? [String: Any] else {
                return Entry(shortcut: shortcut, isEnabled: true, combo: shortcut.factoryCombo)
            }
            let enabled = Self.bool(entry["enabled"]) ?? true
            var combo = shortcut.factoryCombo
            if let value = entry["value"] as? [String: Any], let parameters = value["parameters"] as? [Any],
               parameters.count == 3, let keyCode = Self.int(parameters[1]), let mask = Self.int(parameters[2]),
               keyCode >= 0, keyCode < 0xFFFF, mask >= 0 {
                combo = KeyCombo(keyCode: UInt16(keyCode), modifiers: KeyModifiers(rawValue: UInt(mask)))
            }
            return Entry(shortcut: shortcut, isEnabled: enabled, combo: combo)
        }
        wasRead = true
    }

    public func entry(_ shortcut: Shortcut) -> Entry? {
        entries.first { $0.shortcut == shortcut }
    }

    /// The enabled system shortcut that uses `combo`, if any.
    public func conflict(with combo: KeyCombo) -> Shortcut? {
        entries.first { $0.isEnabled && $0.combo == combo }?.shortcut
    }

    /// Both selection shortcuts (⇧⌘4 and ⌃⇧⌘4) are off, so Exhibit A may use those keys.
    public var selectionShortcutsAreOff: Bool {
        guard wasRead else { return false }
        return [Shortcut.saveSelection, .copySelection].allSatisfy { entry($0)?.isEnabled == false }
    }

    private static func bool(_ value: Any?) -> Bool? {
        if let bool = value as? Bool { return bool }
        if let number = value as? NSNumber { return number.boolValue }
        if let int = value as? Int { return int != 0 }
        return nil
    }

    private static func int(_ value: Any) -> Int? {
        if let int = value as? Int { return int }
        if let number = value as? NSNumber { return number.intValue }
        return nil
    }
}
