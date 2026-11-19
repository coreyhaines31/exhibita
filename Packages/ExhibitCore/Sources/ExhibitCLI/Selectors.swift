import ExhibitCore
import ExhibitPlanning
import ExhibitTargets
import Foundation

/// The CLI's name for a selector. The type lives in `ExhibitPlanning`, which the editor shares; this alias keeps the
/// CLI's code reading as it always has, and shadows Objective-C's `Selector` inside this module.
typealias Selector = MarkSelector

extension MarkSelector {
    static let selectableKinds: [TargetKind] = [.email, .key, .card, .phone, .face, .text]

    static func parseKind(_ raw: String) throws -> TargetKind {
        let kind = TargetKind(rawValue: raw.lowercased())
        guard selectableKinds.contains(kind) else {
            throw CLIError.usage("Unknown kind \"\(raw)\". Use one of: "
                                 + selectableKinds.map(\.rawValue).joined(separator: ", ") + ".")
        }
        return kind
    }
}

extension Candidate {
    var report: CandidateReport {
        CandidateReport(text: text, kind: kind?.rawValue ?? "rect", rect: OutputRect(rect))
    }
}

extension SelectorMatcher {
    /// A hint for a selector that matched nothing.
    static func hint(for selector: MarkSelector) -> String? {
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
        case .rect, .target, .targetPart:
            return nil
        }
    }
}
