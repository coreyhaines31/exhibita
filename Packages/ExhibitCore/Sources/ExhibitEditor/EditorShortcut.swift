import ExhibitShell

/// One key with its modifiers, as the editor matches it. Letters ignore case and keep ⇧ (⇧B is not B), and so do ↩
/// and Space, where ⇧ never changes what is typed (⇧↩ is copy and delete, ↩ copy and close). Other characters
/// drop ⇧, because on some layouts it is part of typing them (/ is ⇧7 on a German keyboard).
public struct EditorShortcut: Hashable, Sendable, Codable {
    /// One character, lowercased, or `returnName` for ↩.
    public let key: String
    public let modifiers: KeyModifiers

    public static let returnName = "return"
    public static let returnKey = EditorShortcut(returnName)

    public init(_ key: String, _ modifiers: KeyModifiers = []) {
        let key = key == Self.returnName ? key : key.lowercased()
        var modifiers = modifiers.intersection(.all)
        if !Self.keepsShift(key) { modifiers.remove(.shift) }
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

    /// Letters, ↩ and Space: keys where ⇧ is a modifier rather than part of the character.
    private static func keepsShift(_ key: String) -> Bool {
        isLetter(key) || key == returnName || key == " "
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
