import ExhibitCore
import ExhibitInterpret
import Foundation

/// What `say` did, in words a person reads after the marks appear: "Blurred 4 emails, circled "Pricing". Couldn't
/// find: logout link." Every mark is named, because about one model answer in ten is wrong and the summary is how
/// a person notices. Text comes from the targets, where sensitive values are already masked.
struct SaySummary {
    struct Operation: Encodable {
        var mark: String
        var summary: String
        var targetIDs: [UUID]
        var label: String?
    }

    let operations: [Operation]
    let sentence: String

    init(interpretation: Interpretation, targets: [Target]) {
        let operations = interpretation.operations.map { operation in
            let marked = targets.filter { operation.targetIDs(in: targets).contains($0.id) }
            return Operation(mark: operation.mark.rawValue,
                             summary: Self.phrase(operation.mark, marked: marked, label: operation.label),
                             targetIDs: marked.map(\.id), label: operation.label)
        }
        var sentence = Self.capitalized(operations.map(\.summary).joined(separator: ", "))
        if !sentence.isEmpty { sentence += "." }
        if !interpretation.notFound.isEmpty {
            sentence += (sentence.isEmpty ? "" : " ") + "Couldn't find: "
                + interpretation.notFound.joined(separator: ", ") + "."
        }
        self.operations = operations
        self.sentence = sentence
    }

    static func phrase(_ mark: MarkKind, marked: [Target], label: String?) -> String {
        let what = names(marked)
        let quotedLabel = label.map { "\"\(clipped($0))\"" } ?? ""
        switch mark {
        case .blur: return "blurred \(what)"
        case .highlight: return "highlighted \(what)"
        case .circle: return "circled \(what)"
        case .box: return "boxed \(what)"
        case .arrow: return "pointed at \(what)" + (label == nil ? "" : " with \(quotedLabel)")
        case .text: return "labelled \(what) \(quotedLabel)"
        case .step: return "numbered \(what)"
        }
    }

    /// "\"Pricing\"", "\"Reply\" and \"Forward\"", "4 emails", "\"Total\", 2 emails and 1 key".
    static func names(_ targets: [Target]) -> String {
        let lines = targets.filter { $0.kind == .text }
        var parts: [String] = lines.count > 3
            ? ["\(lines.count) lines"]
            : lines.map { "\"\(clipped($0.text ?? ""))\"" }
        var counts: [(TargetKind, Int)] = []
        for target in targets where target.kind != .text {
            if let index = counts.firstIndex(where: { $0.0 == target.kind }) {
                counts[index].1 += 1
            } else {
                counts.append((target.kind, 1))
            }
        }
        parts += counts.map { kind, count in "\(count) \(noun(kind, plural: count != 1))" }
        guard parts.count > 1 else { return parts.first ?? "nothing" }
        return parts.dropLast().joined(separator: ", ") + " and " + (parts.last ?? "")
    }

    static func noun(_ kind: TargetKind, plural: Bool) -> String {
        let singular = switch kind {
        case .email: "email"
        case .key: "key"
        case .card: "card number"
        case .phone: "phone number"
        case .face: "face"
        default: kind.rawValue
        }
        return plural ? singular + "s" : singular
    }

    static func clipped(_ text: String, limit: Int = 40) -> String {
        text.count <= limit ? text : String(text.prefix(limit - 3)) + "..."
    }

    static func capitalized(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }
}
