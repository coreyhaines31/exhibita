import ExhibitCore
import Foundation

/// One way of saying what a mark goes on. Each selector is resolved, counted and reported on its own. The CLI calls
/// this `Selector`.
public enum MarkSelector: Equatable, Sendable {
    /// Case-insensitive substring inside text targets. `--text` and `--to`.
    case text(String)
    /// A regular expression over text targets.
    case regex(String)
    /// Every target of a kind.
    case kind(TargetKind)
    /// Explicit pixels, top-left origin.
    case rect(PixelRect)
    /// One target by id. Only from interpreters, which name targets; there is no flag for it.
    case target(UUID)
    /// Part of one target's text, as a UTF-16 range, the way `--to` narrows to a phrase. Only from interpreters.
    case targetPart(UUID, NSRange)

    /// The selector as it would be typed, for reports and errors.
    public var description: String {
        switch self {
        case .text(let text): "--text \(Self.quoted(text))"
        case .regex(let pattern): "--regex \(Self.quoted(pattern))"
        case .kind(let kind): "--kind \(kind.rawValue)"
        case .rect(let rect): "--rect \(Self.number(rect.x)),\(Self.number(rect.y)),\(Self.number(rect.width)),"
            + Self.number(rect.height)
        case .target(let id): "target \(id.uuidString)"
        case .targetPart(let id, let range):
            "target \(id.uuidString) characters \(range.location)..<\(range.location + range.length)"
        }
    }

    /// Whether resolving needs targets from the image.
    public var needsTargets: Bool {
        if case .rect = self { return false }
        return true
    }

    private static func quoted(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    private static func number(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }
}

/// Something a selector matched.
public struct Candidate: Equatable, Sendable {
    public var rect: PixelRect
    public var targetID: UUID?
    /// The matched text, taken from the masked line text, so it never holds a sensitive value.
    public var text: String?
    /// nil for an explicit `--rect`.
    public var kind: TargetKind?

    public init(rect: PixelRect, targetID: UUID? = nil, text: String? = nil, kind: TargetKind? = nil) {
        self.rect = rect
        self.targetID = targetID
        self.text = text
        self.kind = kind
    }
}

public enum SelectorMatcher {
    /// Everything `selector` matches in `targets`, in the targets' reading order.
    public static func candidates(for selector: MarkSelector, in targets: [Target]) throws -> [Candidate] {
        switch selector {
        case .rect(let rect):
            return [Candidate(rect: rect.standardized)]
        case .target(let id):
            return targets.filter { $0.id == id }.map {
                Candidate(rect: $0.rect.standardized, targetID: $0.id, text: $0.text, kind: $0.kind)
            }
        case .targetPart(let id, let range):
            return targets.filter { $0.id == id }.map { target in
                guard let text = target.text, let found = candidate(target, text: text, range: range) else {
                    return Candidate(rect: target.rect.standardized, targetID: target.id, text: target.text,
                                     kind: target.kind)
                }
                return found
            }
        case .kind(let kind):
            return targets.filter { $0.kind == kind }.map {
                Candidate(rect: $0.rect.standardized, targetID: $0.id, text: $0.text, kind: $0.kind)
            }
        case .text(let needle):
            guard !needle.isEmpty else { throw PlanError.usage("--text needs a non-empty string.") }
            // Both sides folded, so "Acme" matches a line OCR read as "Астe". Folding keeps offsets.
            let folded = Confusables.fold(needle)
            return textTargets(targets).flatMap { target, text in
                occurrences(of: folded, in: Confusables.fold(text)).compactMap { candidate(target, text: text, range: $0) }
            }
        case .regex(let pattern):
            let expression: NSRegularExpression
            do {
                expression = try NSRegularExpression(pattern: pattern)
            } catch {
                throw PlanError.usage("--regex \"\(pattern)\" is not a valid regular expression.")
            }
            return textTargets(targets).flatMap { target, text in
                expression.matches(in: Confusables.fold(text), range: NSRange(location: 0, length: text.utf16.count))
                    .map(\.range).filter { $0.length > 0 }
                    .compactMap { candidate(target, text: text, range: $0) }
            }
        }
    }

    private static func textTargets(_ targets: [Target]) -> [(Target, String)] {
        targets.compactMap { target in
            guard target.kind == .text, let text = target.text else { return nil }
            return (target, text)
        }
    }

    /// Non-overlapping case-insensitive occurrences, as UTF-16 ranges.
    private static func occurrences(of needle: String, in text: String) -> [NSRange] {
        let haystack = text as NSString
        var ranges: [NSRange] = []
        var searchStart = 0
        while searchStart < haystack.length {
            let found = haystack.range(of: needle, options: [.caseInsensitive],
                                       range: NSRange(location: searchStart, length: haystack.length - searchStart))
            guard found.location != NSNotFound, found.length > 0 else { break }
            ranges.append(found)
            searchStart = found.location + found.length
        }
        return ranges
    }

    private static func candidate(_ target: Target, text: String, range: NSRange) -> Candidate? {
        guard let rect = target.rect(forUTF16Range: range) else { return nil }
        return Candidate(rect: rect.standardized, targetID: target.id, text: (text as NSString).substring(with: range),
                         kind: .text)
    }
}
