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
public enum EditorCommand: Equatable, Sendable {
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
}

/// The spec's Keys table, plus / for a typed instruction.
public enum EditorKeymap {
    public static func command(for key: EditorKey, modifiers: KeyModifiers) -> EditorCommand? {
        let modifiers = modifiers.intersection(.all)
        switch key {
        case .returnKey: return modifiers.isEmpty ? .copyAndClose : nil
        case .escape: return modifiers.isEmpty ? .close : nil
        case .delete: return modifiers.isEmpty ? .deleteSelection : nil
        case .character(let typed): return command(for: typed.lowercased(), modifiers: modifiers)
        }
    }

    /// Keys held with modifiers, by modifiers then letter.
    private static let modified: [KeyModifiers: [String: EditorCommand]] = [
        [.shift]: ["b": .blurAllSensitive],
        [.command]: ["z": .undo, "s": .save],
        [.command, .shift]: ["z": .redo, "c": .copyPath]
    ]

    private static func command(for letter: String, modifiers: KeyModifiers) -> EditorCommand? {
        // "/" needs ⇧ on some layouts, so ⇧ is allowed with it.
        if letter == "/", modifiers.isSubset(of: [.shift]) { return .typeInstruction }
        guard modifiers.isEmpty else { return modified[modifiers]?[letter] }
        if letter == "d" { return .dictate }
        if let tool = EditorTool.allCases.first(where: { $0.key.lowercased() == letter }) { return .tool(tool) }
        if let color = MarkColor.allCases.first(where: { $0.key == letter }) { return .color(color) }
        return nil
    }
}
