import ExhibitCore
import Foundation

/// Turns clauses into operations. Each `add` returns a reason to decline, or nil.
struct GrammarParser {
    let matcher: GrammarMatcher
    private(set) var operations: [InterpretedOperation] = []
    private(set) var notFound: [String] = []

    init(matcher: GrammarMatcher) {
        self.matcher = matcher
    }

    private static let referBack: Set<String> = ["it", "that", "this", "them"]
    private static let captionWords: Set<String> = ["saying", "labelled", "labeled", "captioned", "reading", "as"]
    private static let locators: [[String]] = [["next", "to"], ["on"], ["by"], ["beside"], ["near"], ["over"],
                                               ["above"], ["below"], ["under"], ["to"], ["at"]]

    mutating func add(_ clause: GrammarClause) -> String? {
        switch clause.mark {
        case .text: return addLabel(clause)
        case .arrow: return addArrow(clause.rest)
        case .step: return addSteps(clause.rest)
        default: return addMark(clause.mark, objects: clause.rest)
        }
    }

    private mutating func addMark(_ mark: MarkKind, objects: [String], label: String? = nil) -> String? {
        switch resolveObjects(objects, for: mark) {
        case .failure(let reason):
            return reason.message
        case .success(let (picks, missing)):
            notFound += missing
            if !picks.isEmpty { operations.append(InterpretedOperation(mark: mark, picks: picks, label: label)) }
            return nil
        }
    }

    private mutating func addArrow(_ rest: [String]) -> String? {
        var rest = rest
        while let first = rest.first, ["on", "at", "to", "pointing"].contains(first) { rest.removeFirst() }
        if let split = rest.firstIndex(where: Self.captionWords.contains), split > 0 {
            return addMark(.arrow, objects: Array(rest[..<split]), label: Self.text(rest[(split + 1)...]))
        }
        return addMark(.arrow, objects: rest)
    }

    private mutating func addSteps(_ rest: [String]) -> String? {
        guard let first = rest.first, GrammarLexicon.ordinals.contains(first), rest.contains("step") else {
            return addMark(.step, objects: rest)
        }
        // "step one email step two password": one step operation, in the order said.
        let pieces = rest.split(separator: "step").map { piece in
            Array(piece.drop { GrammarLexicon.ordinals.contains($0) })
        }
        let joined = pieces.filter { !$0.isEmpty }.flatMap { $0 + ["and"] }.dropLast()
        return addMark(.step, objects: Array(joined))
    }

    /// "label it needs triage" after another clause, "label X as Y", "add a label saying Y next to X",
    /// "write Y next to X".
    private mutating func addLabel(_ clause: GrammarClause) -> String? {
        var rest = clause.rest
        if let first = rest.first, Self.referBack.contains(first), let previous = operations.last {
            rest.removeFirst()
            if let first = rest.first, Self.captionWords.contains(first) { rest.removeFirst() }
            guard !rest.isEmpty else { return "a label with no words" }
            if previous.mark == .arrow, previous.label == nil {
                operations[operations.count - 1].label = Self.text(rest[...])
            } else {
                operations.append(InterpretedOperation(mark: .text, picks: previous.picks, label: Self.text(rest[...])))
            }
            return nil
        }
        if let first = rest.first, ["saying", "says", "reading"].contains(first) || clause.verb == ["write"] {
            if Self.captionWords.contains(first) || first == "says" { rest.removeFirst() }
            return addLabelBeforeObject(rest)
        }
        return addLabelAfterObject(rest)
    }

    /// "rotate this next to the payments key": the last locator whose object resolves.
    private mutating func addLabelBeforeObject(_ words: [String]) -> String? {
        for index in stride(from: words.count - 1, through: 1, by: -1) {
            guard let locator = Self.locators.first(where: { Array(words[index...].prefix($0.count)) == $0 }) else {
                continue
            }
            let object = Array(words[(index + locator.count)...])
            if case .success = resolveObjects(object, for: .text) {
                let labelEnd = locator == ["to"] && words[index - 1] == "next" ? index - 1 : index
                return addMark(.text, objects: object, label: Self.text(words[..<labelEnd]))
            }
        }
        return "could not tell the label from what it labels"
    }

    /// "the Total as checked", or "Pricing new" by the longest leading phrase that names one target.
    private mutating func addLabelAfterObject(_ words: [String]) -> String? {
        if let split = words.firstIndex(where: { ["as", "saying", "with", "reading"].contains($0) }), split > 0 {
            return addMark(.text, objects: Array(words[..<split]), label: Self.text(words[(split + 1)...]))
        }
        for end in stride(from: words.count - 1, through: 1, by: -1) {
            let object = Array(words[..<end])
            if case .success(let (picks, missing)) = resolveObjects(object, for: .text), missing.isEmpty,
               picks.count == 1 {
                return addMark(.text, objects: object, label: Self.text(words[end...]))
            }
        }
        return "could not tell the label from what it labels"
    }

    private static func text(_ words: ArraySlice<String>) -> String {
        words.joined(separator: " ")
    }
}

struct Decline: Error {
    var message: String
}

extension GrammarParser {
    /// Picks for an object phrase, plus kinds the screen has none of. Fails on anything unsure.
    func resolveObjects(_ words: [String], for mark: MarkKind) -> Result<([TargetPick], [String]), Decline> {
        var words = words
        while let first = words.first, GrammarLexicon.prepositions.contains(first) { words.removeFirst() }
        if words.count >= 2, GrammarLexicon.colors.contains(words[words.count - 1]), words[words.count - 2] == "in" {
            words.removeLast(2)
        }
        guard !words.isEmpty else { return .failure(Decline(message: "nothing named")) }
        var items = items(in: words, for: mark)
        breakTies(&items)
        var picks: [TargetPick] = []
        var missing: [String] = []
        for item in items {
            switch item {
            case .targets(let targets): picks += targets.map { .id($0.id) }
            case .kinds(let kinds): picks += kinds.map(TargetPick.kind)
            case .notFound(let phrase): missing.append(phrase)
            case .ambiguous(let found): return .failure(Decline(message: "\(found.count) equal matches"))
            case .unmatched(let phrase): return .failure(Decline(message: "\"\(phrase)\" is not on the screen as text"))
            case .decline(let reason): return .failure(Decline(message: reason))
            }
        }
        return .success((picks, missing))
    }

    /// The whole phrase if it resolves; otherwise its parts split at "and", each part split into whole lines if
    /// needed ("reply forward" as "Reply" and "Forward").
    private func items(in words: [String], for mark: MarkKind) -> [ItemResult] {
        let whole = matcher.resolve(words, for: mark)
        if Self.resolved(whole) { return [whole] }
        let chunks = words.split(separator: "and").map(Array.init).filter { !$0.isEmpty }
        let parts = chunks.flatMap { chunk -> [[String]] in
            if chunks.count > 1, Self.resolved(matcher.resolve(chunk, for: mark)) { return [chunk] }
            let bare = Array(chunk.drop { GrammarLexicon.determiners.contains($0) })
            if let segments = matcher.segment(bare), segments.count > 1 { return segments }
            return [chunk]
        }
        guard parts.count > 1 else { return [whole] }
        return parts.map { matcher.resolve($0, for: mark) }
    }

    private static func resolved(_ result: ItemResult) -> Bool {
        switch result {
        case .targets, .kinds, .notFound: true
        default: false
        }
    }

    /// An ambiguous part of a list goes to the candidate nearest the parts that were not ambiguous, when that
    /// candidate is clearly nearest: "number reply forward and archive" takes the Archive button beside Forward.
    private func breakTies(_ items: inout [ItemResult]) {
        let anchors = items.flatMap { item -> [Target] in
            if case .targets(let targets) = item { return targets }
            return []
        }
        guard !anchors.isEmpty else { return }
        let centre = PixelPoint(x: anchors.map(\.rect.midX).reduce(0, +) / Double(anchors.count),
                                y: anchors.map(\.rect.midY).reduce(0, +) / Double(anchors.count))
        for (index, item) in items.enumerated() {
            guard case .ambiguous(let found) = item else { continue }
            let ranked = found.map { (target: $0, distance: hypot($0.rect.midX - centre.x, $0.rect.midY - centre.y)) }
                .sorted { $0.distance < $1.distance }
            if ranked.count >= 2, ranked[0].distance * 2 < ranked[1].distance {
                items[index] = .targets([ranked[0].target])
            }
        }
    }
}
