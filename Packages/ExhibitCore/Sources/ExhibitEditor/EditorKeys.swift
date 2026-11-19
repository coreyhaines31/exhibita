import ExhibitCore
import ExhibitShell

/// A key the editor reads. The app turns `NSEvent`s into these; letters arrive as typed, case ignored.
public enum EditorKey: Equatable, Sendable {
    case character(String)
    case returnKey
    case escape
    case delete

    /// macOS virtual key codes for the keys that are not characters.
    public static func special(keyCode: UInt16) -> EditorKey? {
        switch keyCode {
        case 0x24, 0x4C: .returnKey
        case 0x35: .escape
        case 0x33, 0x75: .delete
        default: nil
        }
    }
}

/// What a key asks for.
public enum EditorCommand: Hashable, Sendable {
    case tool(EditorTool)
    case color(MarkColor)
    /// ⇧B: blur every detected secret not already covered.
    case blurAllSensitive
    case undo
    case redo
    case deleteSelection
    /// ↩: copy the flattened image and close.
    case copyAndClose
    /// ⌘S: save a file.
    case save
    /// ⌘⇧C: export to a file and copy its path.
    case copyPath
    /// Esc: close; the capture stays in history.
    case close
    /// D, held: dictate. The app starts listening on key-down (repeats ignored) and stops on key-up.
    case dictate
    /// /: type an instruction instead of saying it.
    case typeInstruction

    /// Commands the app carries out (clipboard, files, windows). The editor handles the rest itself.
    public var isAppCommand: Bool {
        switch self {
        case .copyAndClose, .save, .copyPath, .close, .dictate, .typeInstruction: true
        default: false
        }
    }

    /// Commands whose key a person can change, in the order Settings lists them. Esc, ⌫, ⌘Z and ⇧⌘Z stay
    /// fixed: they mean the same in every Mac app, and Esc is also how dictation and the key recorder are
    /// cancelled.
    public static let remappable: [EditorCommand] = EditorTool.toolbarOrder.map { .tool($0) }
        + MarkColor.allCases.map { .color($0) }
        + [.blurAllSensitive, .dictate, .typeInstruction, .copyAndClose, .save, .copyPath]

    /// The commands whose key never changes.
    public static let fixed: [EditorCommand] = [.undo, .redo, .deleteSelection, .close]

    public var isRemappable: Bool { Self.remappable.contains(self) }

    /// The name stored in preferences; stable across versions.
    public var id: String {
        switch self {
        case .tool(let tool): "tool.\(tool.rawValue)"
        case .color(let color): "color.\(color.rawValue)"
        case .blurAllSensitive: "blurAllSensitive"
        case .undo: "undo"
        case .redo: "redo"
        case .deleteSelection: "deleteSelection"
        case .copyAndClose: "copyAndClose"
        case .save: "save"
        case .copyPath: "copyPath"
        case .close: "close"
        case .dictate: "dictate"
        case .typeInstruction: "typeInstruction"
        }
    }

    public init?(id: String) {
        guard let command = (Self.remappable + Self.fixed).first(where: { $0.id == id }) else { return nil }
        self = command
    }

    /// What Settings, tooltips and messages call it.
    public var title: String {
        switch self {
        case .tool(let tool): tool.title
        case .color(let color): color.title
        case .blurAllSensitive: "Blur secrets"
        case .undo: "Undo"
        case .redo: "Redo"
        case .deleteSelection: "Delete mark"
        case .copyAndClose: "Copy and close"
        case .save: "Save"
        case .copyPath: "Copy path"
        case .close: "Close"
        case .dictate: "Dictate"
        case .typeInstruction: "Type an instruction"
        }
    }

    /// A few words on what it does, for Settings.
    public var detail: String {
        switch self {
        case .tool(.select): "Move, resize and delete marks."
        case .tool(.arrow): "Draw an arrow."
        case .tool(.circle): "Circle text or draw a circle."
        case .tool(.blur): "Blur a line or an area."
        case .tool(.highlight): "Highlight a line or an area."
        case .tool(.text): "Type a label."
        case .tool(.box): "Box text or draw a box."
        case .tool(.step): "Place numbered steps."
        case .color(let color): "\(color.title) for new marks and the selected one."
        case .blurAllSensitive: "Blur every email, key, card and phone number found."
        case .dictate: "Hold and say what to change; let go to apply."
        case .typeInstruction: "Type what to change instead of saying it."
        case .copyAndClose: "Copy the marked-up image and close the editor."
        case .save: "Save the marked-up image as a file."
        case .copyPath: "Write the image to a file and copy its path."
        case .undo, .redo, .deleteSelection, .close: ""
        }
    }

    /// The key it has until someone changes it. Nil for the fixed commands, which are not shortcuts.
    public var defaultShortcut: EditorShortcut? {
        switch self {
        case .tool(let tool): EditorShortcut(tool.defaultKey)
        case .color(let color): EditorShortcut(color.defaultKey)
        case .blurAllSensitive: EditorShortcut("b", [.shift])
        case .dictate: EditorShortcut("d")
        case .typeInstruction: EditorShortcut("/")
        case .copyAndClose: .returnKey
        case .save: EditorShortcut("s", [.command])
        case .copyPath: EditorShortcut("c", [.command, .shift])
        case .undo, .redo, .deleteSelection, .close: nil
        }
    }
}

/// One key with its modifiers, as the editor matches it. Letters ignore case and keep ⇧ (⇧B is not B); other
/// characters drop ⇧, because on some layouts it is part of typing them (/ is ⇧7 on a German keyboard).
public struct EditorShortcut: Hashable, Sendable, Codable {
    /// One character, lowercased, or `returnName` for ↩.
    public let key: String
    public let modifiers: KeyModifiers

    public static let returnName = "return"
    public static let returnKey = EditorShortcut(returnName)

    public init(_ key: String, _ modifiers: KeyModifiers = []) {
        let key = key == Self.returnName ? key : key.lowercased()
        var modifiers = modifiers.intersection(.all)
        if !Self.isLetter(key) { modifiers.remove(.shift) }
        self.key = key
        self.modifiers = modifiers
    }

    /// A key press as a shortcut, or nil for keys that can't be one: Esc, ⌫, Tab, arrows and function keys.
    public init?(key: EditorKey, modifiers: KeyModifiers) {
        switch key {
        case .returnKey: self.init(Self.returnName, modifiers)
        case .escape, .delete: return nil
        case .character(let typed):
            guard typed.count == 1, let scalar = typed.unicodeScalars.first,
                  !scalar.properties.generalCategory.isControlOrPrivate else { return nil }
            self.init(typed, modifiers)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(try container.decode(String.self, forKey: .key),
                  try container.decode(KeyModifiers.self, forKey: .modifiers))
    }

    public var isLetter: Bool { Self.isLetter(key) }

    /// "A", "⇧B", "⌘S", "↩", "Space".
    public var display: String {
        let name = switch key {
        case Self.returnName: "↩"
        case " ": "Space"
        default: key.uppercased()
        }
        return modifiers.symbols + name
    }

    private static func isLetter(_ key: String) -> Bool {
        key.count == 1 && key.lowercased() != key.uppercased()
    }
}

private extension Unicode.GeneralCategory {
    /// Tab, other control characters and the private-use characters AppKit gives arrows and function keys.
    var isControlOrPrivate: Bool {
        switch self {
        case .control, .privateUse, .format, .unassigned, .surrogate: true
        default: false
        }
    }
}

/// Why a key can't be given to a command.
public enum EditorShortcutIssue: Equatable, Sendable {
    /// Another command has it.
    case usedBy(EditorCommand, EditorShortcut)
    /// Esc, ⌫, ⌘Z or ⇧⌘Z, which never change.
    case fixed(EditorCommand)
    /// Not a key the editor can match: Tab, arrows, function keys.
    case unsupported
    /// The command itself is fixed.
    case notRemappable(EditorCommand)
    /// macOS or the app needs it everywhere: ⌘Q, ⌘W, ⌘H, ⌘M, ⌘, and the like. The key as shown, then its use.
    case reserved(String, String)

    public var message: String {
        switch self {
        case let .usedBy(command, shortcut): "\(command.title) already uses \(shortcut.display)."
        case .fixed(let command): "\(EditorKeymap.fixedDisplay(for: command)) is kept for \(command.title)."
        case .unsupported: "Use a letter, number, symbol, Space or ↩, with or without ⌘ ⌥ ⌃ ⇧."
        case .notRemappable(let command): "\(command.title) always uses \(EditorKeymap.fixedDisplay(for: command))."
        case let .reserved(key, use): "\(key) is kept for \(use) everywhere on the Mac."
        }
    }
}

/// The editor's keys: each remappable command's default, with a person's changes on top. Only the changes are
/// stored, so a default that moves in a later version reaches everyone who left that command alone.
public struct EditorKeymap: Equatable, Sendable {
    /// The keys someone picked, only where they differ from the default.
    public private(set) var custom: [EditorCommand: EditorShortcut]

    public init(custom: [EditorCommand: EditorShortcut] = [:]) {
        self.custom = custom.filter { command, shortcut in
            command.isRemappable && shortcut != command.defaultShortcut
        }
    }

    public static let standard = EditorKeymap()

    /// ⌘Z and ⇧⌘Z. Esc and ⌫ are not characters, so they are matched on their own.
    private static let fixedShortcuts: [(EditorShortcut, EditorCommand)] = [
        (EditorShortcut("z", [.command]), .undo),
        (EditorShortcut("z", [.command, .shift]), .redo)
    ]

    /// Keys macOS or the app itself needs in every window, never given to an editor command.
    public static let reservedShortcuts: [(EditorShortcut, String)] = [
        (EditorShortcut("q", [.command]), "Quit"),
        (EditorShortcut("q", [.command, .shift]), "Log Out"),
        (EditorShortcut("q", [.command, .control]), "Lock Screen"),
        (EditorShortcut("w", [.command]), "Close Window"),
        (EditorShortcut("w", [.command, .option]), "Close All"),
        (EditorShortcut("h", [.command]), "Hide"),
        (EditorShortcut("h", [.command, .option]), "Hide Others"),
        (EditorShortcut("m", [.command]), "Minimize"),
        (EditorShortcut("m", [.command, .option]), "Minimize All"),
        (EditorShortcut(",", [.command]), "Settings"),
        (EditorShortcut(" ", [.command]), "Spotlight"),
        (EditorShortcut(" ", [.command, .control]), "the Character Viewer"),
        (EditorShortcut(" ", [.control]), "switching input sources"),
        (EditorShortcut("`", [.command]), "switching windows"),
        (EditorShortcut("f", [.command, .control]), "Full Screen")
    ]

    static func reservedUse(of shortcut: EditorShortcut) -> String? {
        reservedShortcuts.first { $0.0 == shortcut }?.1
    }

    public static func fixedDisplay(for command: EditorCommand) -> String {
        switch command {
        case .close: "Esc"
        case .deleteSelection: "⌫"
        default: fixedShortcuts.first { $0.1 == command }?.0.display ?? ""
        }
    }

    /// The key a remappable command has now; nil for the fixed ones.
    public func shortcut(for command: EditorCommand) -> EditorShortcut? {
        custom[command] ?? command.defaultShortcut
    }

    /// What to show for a command, fixed ones included: "A", "⌘S", "Esc".
    public func display(for command: EditorCommand) -> String {
        shortcut(for: command)?.display ?? Self.fixedDisplay(for: command)
    }

    public func isCustom(_ command: EditorCommand) -> Bool { custom[command] != nil }

    public var isStandard: Bool { custom.isEmpty }

    /// The command a key press asks for, if any.
    public func command(for key: EditorKey, modifiers: KeyModifiers) -> EditorCommand? {
        let modifiers = modifiers.intersection(.all)
        switch key {
        case .escape: return modifiers.isEmpty ? .close : nil
        case .delete: return modifiers.isEmpty ? .deleteSelection : nil
        case .character, .returnKey: break
        }
        guard let pressed = EditorShortcut(key: key, modifiers: modifiers) else { return nil }
        if let fixed = Self.fixedShortcuts.first(where: { $0.0 == pressed }) { return fixed.1 }
        // A key someone picked wins over a default that later came to use the same key.
        if let picked = EditorCommand.remappable.first(where: { custom[$0] == pressed }) { return picked }
        return EditorCommand.remappable.first { custom[$0] == nil && $0.defaultShortcut == pressed }
    }

    /// Whether a key coming up ends a hold of the dictate key. Modifiers may change while it is held, so only the
    /// key itself is compared.
    public func releasesDictation(_ key: EditorKey) -> Bool {
        guard let dictate = shortcut(for: .dictate),
              let released = EditorShortcut(key: key, modifiers: dictate.modifiers) else { return false }
        return released.key == dictate.key
    }

    /// Checks a key someone is about to give `command`.
    public func issue(assigning shortcut: EditorShortcut, to command: EditorCommand) -> EditorShortcutIssue? {
        guard command.isRemappable else { return .notRemappable(command) }
        if let use = Self.reservedUse(of: shortcut) { return .reserved(shortcut.display, use) }
        if let fixed = Self.fixedShortcuts.first(where: { $0.0 == shortcut }) { return .fixed(fixed.1) }
        for other in EditorCommand.remappable where other != command && self.shortcut(for: other) == shortcut {
            return .usedBy(other, shortcut)
        }
        return nil
    }

    /// Checks a key press recorded in Settings for `command`.
    public func issue(recording key: EditorKey, modifiers: KeyModifiers,
                      for command: EditorCommand) -> EditorShortcutIssue? {
        switch key {
        case .escape: return .fixed(.close)
        case .delete: return .fixed(.deleteSelection)
        case .character, .returnKey: break
        }
        // Tab with ⌘ is the app switcher, and with ⌃ moves between controls; plain Tab is not a shortcut at all.
        if key == .character("\t"), !modifiers.isDisjoint(with: [.command, .control]) {
            return .reserved(modifiers.intersection(.all).symbols + "Tab",
                             modifiers.contains(.command) ? "the app switcher" : "moving between controls")
        }
        guard let shortcut = EditorShortcut(key: key, modifiers: modifiers) else { return .unsupported }
        return issue(assigning: shortcut, to: command)
    }

    /// Gives `command` a key, or returns why not. Giving it its default clears the change.
    public mutating func assign(_ shortcut: EditorShortcut, to command: EditorCommand) -> EditorShortcutIssue? {
        if let issue = issue(assigning: shortcut, to: command) { return issue }
        custom[command] = shortcut == command.defaultShortcut ? nil : shortcut
        return nil
    }

    /// Puts a command back on its default key. Refused when someone else took that key in the meantime.
    @discardableResult
    public mutating func reset(_ command: EditorCommand) -> EditorShortcutIssue? {
        guard let standard = command.defaultShortcut, custom[command] != nil else { return nil }
        for other in EditorCommand.remappable where other != command && shortcut(for: other) == standard {
            return .usedBy(other, standard)
        }
        custom[command] = nil
        return nil
    }

    public mutating func resetAll() {
        custom = [:]
    }

    // MARK: - Storage

    /// The changes by command id, for preferences.
    public var stored: [String: EditorShortcut] {
        Dictionary(uniqueKeysWithValues: custom.map { ($0.key.id, $0.value) })
    }

    /// Reads stored changes. Unknown commands (from a newer version) and keys that would clash are dropped.
    public init(stored: [String: EditorShortcut]) {
        var custom: [EditorCommand: EditorShortcut] = [:]
        for command in EditorCommand.remappable {
            guard let shortcut = stored[command.id],
                  !Self.fixedShortcuts.contains(where: { $0.0 == shortcut }),
                  Self.reservedUse(of: shortcut) == nil,
                  !custom.values.contains(shortcut) else { continue }
            custom[command] = shortcut
        }
        self.init(custom: custom)
    }

    /// The command whose picked key hides this command's default, if any. Only a default that changed in a later
    /// version can end up there; Settings says so on the row.
    public func shadowing(_ command: EditorCommand) -> EditorCommand? {
        guard custom[command] == nil, let standard = command.defaultShortcut else { return nil }
        return EditorCommand.remappable.first { $0 != command && custom[$0] == standard }
    }
}
