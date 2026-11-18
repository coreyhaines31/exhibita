import ExhibitCore
import Foundation

extension TargetPick {
    /// The targets this pick names, in reading order. `.text` has the meaning of the CLI's `--text`: every text line
    /// containing the string, ignoring case and look-alike letters.
    public func targets(in targets: [Target]) -> [Target] {
        switch self {
        case .id(let id):
            return targets.filter { $0.id == id }
        case .kind(let kind):
            return targets.filter { $0.kind == kind }
        case .text(let needle):
            let folded = Confusables.fold(needle)
            guard !folded.isEmpty else { return [] }
            return targets.filter { target in
                guard target.kind == .text, let text = target.text else { return false }
                return Confusables.fold(text).range(of: folded, options: .caseInsensitive) != nil
            }
        }
    }
}

extension InterpretedOperation {
    /// Every target the operation's picks name, without repeats.
    public func targetIDs(in targets: [Target]) -> Set<UUID> {
        Set(picks.flatMap { $0.targets(in: targets) }.map(\.id))
    }

    /// The operation as one `marks.json` entry for `exhibit apply` (see `docs/cli.md`). Target ids become the
    /// targets' rects, kinds become `kinds` and text picks become `text`. The interpreter has already decided how
    /// many things to mark, so the entry asks for every match.
    public func applyEntry(in targets: [Target]) -> ApplyEntry {
        var entry = ApplyEntry(kind: mark.rawValue)
        for pick in picks {
            switch pick {
            case .id(let id):
                if let target = targets.first(where: { $0.id == id }) { entry.rect.append(target.rect.standardized) }
            case .kind(let kind):
                entry.kinds.append(kind.rawValue)
            case .text(let text):
                entry.text.append(text)
            }
        }
        entry.label = label
        entry.all = true
        return entry
    }
}

/// One entry of `marks.json`, in the CLI's field names. Empty selector lists are left out when encoded.
public struct ApplyEntry: Sendable, Equatable, Encodable {
    public var kind: String
    public var rect: [PixelRect] = []
    public var kinds: [String] = []
    public var text: [String] = []
    public var label: String?
    public var all = false

    public init(kind: String) {
        self.kind = kind
    }

    private enum CodingKeys: String, CodingKey {
        case kind, rect, kinds, text, label, all
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        if !rect.isEmpty { try container.encode(rect, forKey: .rect) }
        if !kinds.isEmpty { try container.encode(kinds, forKey: .kinds) }
        if !text.isEmpty { try container.encode(text, forKey: .text) }
        try container.encodeIfPresent(label, forKey: .label)
        if all { try container.encode(all, forKey: .all) }
    }
}
