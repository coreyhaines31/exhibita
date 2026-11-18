import ExhibitCore
import ExhibitTargets
import Foundation

/// One way of saying what a mark goes on. Each selector the user gives is resolved, counted and reported on its own.
enum Selector: Equatable {
    /// Case-insensitive substring inside text targets. `--text` and `--to`.
    case text(String)
    /// A regular expression over text targets.
    case regex(String)
    /// Every target of a kind.
    case kind(TargetKind)
    /// Explicit pixels, top-left origin.
    case rect(PixelRect)
    /// One target by id. Only from `say`, whose interpreters name targets; there is no flag for it.
    case target(UUID)

    /// The selector as it would be typed, for reports and errors.
    var description: String {
        switch self {
        case .text(let text): "--text \(Self.quoted(text))"
        case .regex(let pattern): "--regex \(Self.quoted(pattern))"
        case .kind(let kind): "--kind \(kind.rawValue)"
        case .rect(let rect): "--rect \(Self.number(rect.x)),\(Self.number(rect.y)),\(Self.number(rect.width)),"
            + Self.number(rect.height)
        case .target(let id): "target \(id.uuidString)"
        }
    }

    /// Whether resolving needs targets from the image.
    var needsTargets: Bool {
        if case .rect = self { return false }
        return true
    }

    static let selectableKinds: [TargetKind] = [.email, .key, .card, .phone, .face, .text]

    static func parseKind(_ raw: String) throws -> TargetKind {
        let kind = TargetKind(rawValue: raw.lowercased())
        guard selectableKinds.contains(kind) else {
            throw CLIError.usage("Unknown kind \"\(raw)\". Use one of: "
                                 + selectableKinds.map(\.rawValue).joined(separator: ", ") + ".")
        }
        return kind
    }

    private static func quoted(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    private static func number(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }
}

/// Something a selector matched.
struct Candidate: Equatable {
    var rect: PixelRect
    var targetID: UUID?
    /// The matched text, taken from the masked line text, so it never holds a sensitive value.
    var text: String?
    /// nil for an explicit `--rect`.
    var kind: TargetKind?

    var report: CandidateReport {
        CandidateReport(text: text, kind: kind?.rawValue ?? "rect", rect: OutputRect(rect))
    }
}

enum SelectorMatcher {
    /// Everything `selector` matches in `targets`, in the targets' reading order.
    static func candidates(for selector: Selector, in targets: [Target]) throws -> [Candidate] {
        switch selector {
        case .rect(let rect):
            return [Candidate(rect: rect.standardized)]
        case .target(let id):
            return targets.filter { $0.id == id }.map {
                Candidate(rect: $0.rect.standardized, targetID: $0.id, text: $0.text, kind: $0.kind)
            }
        case .kind(let kind):
            return targets.filter { $0.kind == kind }.map {
                Candidate(rect: $0.rect.standardized, targetID: $0.id, text: $0.text, kind: $0.kind)
            }
        case .text(let needle):
            guard !needle.isEmpty else { throw CLIError.usage("--text needs a non-empty string.") }
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
                throw CLIError.usage("--regex \"\(pattern)\" is not a valid regular expression.")
            }
            return textTargets(targets).flatMap { target, text in
                expression.matches(in: Confusables.fold(text), range: NSRange(location: 0, length: text.utf16.count))
                    .map(\.range).filter { $0.length > 0 }
                    .compactMap { candidate(target, text: text, range: $0) }
            }
        }
    }

    /// A hint for a selector that matched nothing.
    static func hint(for selector: Selector) -> String? {
        switch selector {
        case .text(let text), .regex(let text):
            let kinds = Set(SensitivePatterns.matches(in: text).map(\.kind.rawValue)).sorted()
            if !kinds.isEmpty {
                return "Sensitive text (emails, keys, cards, phone numbers) is masked in targets, so text selectors "
                    + "cannot match it. Use " + kinds.map { "--kind \($0)" }.joined(separator: " ") + " instead."
            }
            return "Run `exhibit targets <input>` to see the text that was read from the image. "
                + "Sensitive values are masked there and are selected with --kind."
        case .kind:
            return "Run `exhibit targets <input>` to see the kinds that were found."
        case .rect, .target:
            return nil
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
