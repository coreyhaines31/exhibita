import ExhibitCore
import ExhibitInterpret
import Foundation

/// Marks grouped by kind, each with the set of targets it covers. Operations of one kind are merged, so "blur the
/// emails and the keys" scores the same as one operation or two. Labels and step order are not scored.
typealias MarkSets = [MarkKind: Set<UUID>]

/// One interpreter's answer to one instruction, scored.
struct Scored: Codable {
    var id: String
    var split: String
    var tags: [String]
    var instruction: String
    /// False when the interpreter declined or failed.
    var answered: Bool
    var exact: Bool
    /// Redaction instructions only: expected targets left uncovered by any blur, and blurs that cover none.
    var missedRedactions: Int?
    var overRedactions: Int?
    var milliseconds: Double
    var output: String
    /// Which interpreter answered: "grammar" or "model" in the chain.
    var answeredBy: String?
    /// The model call alone, when the model was asked.
    var modelMilliseconds: Double?
    /// What the model server reported about that call: load, prompt and output times and token counts.
    var modelTimings: ModelTimings?
    /// Instructions whose answer is "not on the screen": reported as not found, with nothing marked in its place.
    var notFoundCorrect: Bool?
}

enum Scoring {
    static func sets(_ interpretation: Interpretation, in targets: [Target]) -> MarkSets {
        var sets: MarkSets = [:]
        for operation in interpretation.operations {
            sets[operation.mark, default: []].formUnion(operation.targetIDs(in: targets))
        }
        return sets.filter { !$0.value.isEmpty }
    }

    static func sets(_ expectation: Expectation, in targets: [Target]) -> MarkSets {
        var sets: MarkSets = [:]
        for operation in expectation.operations {
            sets[operation.mark, default: []].formUnion(operation.targets.flatMap { $0.resolve(in: targets) }.map(\.id))
        }
        return sets.filter { !$0.value.isEmpty }
    }

    static func score(_ instruction: EvalInstruction, outcome: Result<InterpretOutcome, Error>, targets: [Target],
                      milliseconds: Double) -> Scored {
        let interpretation = (try? outcome.get())?.interpretation
        let expectations = [instruction.expected] + (instruction.alternatives ?? [])
        var scored = Scored(id: instruction.id, split: instruction.split, tags: instruction.tags,
                            instruction: instruction.instruction, answered: interpretation != nil, exact: false,
                            milliseconds: milliseconds, output: describe(outcome, targets: targets))
        if instruction.expected.notFound == true { scored.notFoundCorrect = false }
        guard let interpretation else { return scored }
        let predicted = sets(interpretation, in: targets)
        scored.exact = expectations.contains { expectation in
            sets(expectation, in: targets) == predicted
                && (expectation.notFound ?? false) == !interpretation.notFound.isEmpty
        }
        if instruction.expected.notFound == true {
            scored.notFoundCorrect = !interpretation.notFound.isEmpty && expectations.contains { expectation in
                let expected = sets(expectation, in: targets)
                return predicted.allSatisfy { mark, ids in ids.isSubset(of: expected[mark] ?? []) }
            }
        }
        let expectedBlur = sets(instruction.expected, in: targets)[.blur] ?? []
        if !expectedBlur.isEmpty {
            let byID = Dictionary(uniqueKeysWithValues: targets.map { ($0.id, $0.rect.standardized) })
            let blurred = (predicted[.blur] ?? []).compactMap { byID[$0] }
            let wanted = expectedBlur.compactMap { byID[$0] }
            scored.missedRedactions = wanted.filter { want in !blurred.contains { covers($0, want) } }.count
            scored.overRedactions = blurred.filter { got in !wanted.contains { overlaps(got, $0) } }.count
        }
        return scored
    }

    static func covers(_ outer: PixelRect, _ inner: PixelRect) -> Bool {
        outer.minX - 2 <= inner.minX && outer.minY - 2 <= inner.minY
            && outer.maxX + 2 >= inner.maxX && outer.maxY + 2 >= inner.maxY
    }

    static func overlaps(_ lhs: PixelRect, _ rhs: PixelRect) -> Bool {
        lhs.minX < rhs.maxX && rhs.minX < lhs.maxX && lhs.minY < rhs.maxY && rhs.minY < lhs.maxY
    }

    /// The outcome in a short readable form, naming targets by kind and text.
    static func describe(_ outcome: Result<InterpretOutcome, Error>, targets: [Target]) -> String {
        switch outcome {
        case .failure(let error): return "error: \(error)"
        case .success(.declined(let reason)): return "declined: \(reason)"
        case .success(.understood(let interpretation)):
            var parts = interpretation.operations.map { operation in
                let named = operation.picks.map { pick -> String in
                    switch pick {
                    case .kind(let kind): "kind \(kind.rawValue)"
                    case .text(let text): "text \"\(text)\""
                    case .part: pick.part(in: targets).map { "\"\($0.text)\" in a line" } ?? "?"
                    case .id(let id):
                        targets.first { $0.id == id }.map { $0.text.map { "\"\($0)\"" } ?? $0.kind.rawValue } ?? "?"
                    }
                }
                let label = operation.label.map { " label \"\($0)\"" } ?? ""
                return "\(operation.mark.rawValue) [\(named.joined(separator: ", "))]\(label)"
            }
            if !interpretation.notFound.isEmpty {
                parts.append("not found: " + interpretation.notFound.joined(separator: ", "))
            }
            return parts.isEmpty ? "(nothing)" : parts.joined(separator: "; ")
        }
    }
}
