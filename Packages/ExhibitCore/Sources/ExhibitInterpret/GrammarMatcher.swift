import ExhibitCore
import Foundation

/// What one object phrase ("the emails", "pricing", "this") resolved to.
enum ItemResult: Equatable {
    case targets([Target])
    case kinds([TargetKind])
    /// A kind the screen has none of: reported, not guessed.
    case notFound(String)
    /// Several lines match and the mark draws one: the grammar does not guess.
    case ambiguous([Target])
    /// No lookup answers it.
    case unmatched(String)
    case decline(String)
}

/// Looks object phrases up in the target list: kinds, the pointer, then text lines.
struct GrammarMatcher {
    let targets: [Target]
    let lines: [(target: Target, words: [String])]
    let pointed: Target?

    init(request: InterpretRequest) {
        let listed = TargetListing.listable(request.targets)
        targets = listed
        lines = listed.compactMap { target in
            guard target.kind == .text, let text = target.text else { return nil }
            return (target, Words.of(text))
        }
        pointed = request.pointer.flatMap { TargetListing.target(at: $0, in: listed) }
    }

    /// Resolves one object phrase for a mark.
    func resolve(_ phrase: [String], for mark: MarkKind) -> ItemResult {
        var words = phrase
        var every = false
        while let first = words.first,
              GrammarLexicon.determiners.contains(first) || GrammarLexicon.everyWords.contains(first) {
            every = every || GrammarLexicon.everyWords.contains(first)
            words.removeFirst()
        }
        guard !words.isEmpty else { return .decline("nothing named") }
        if GrammarLexicon.deictic.contains(words) {
            return pointed.map { .targets([$0]) } ?? .decline("\"\(words.joined(separator: " "))\" needs the pointer")
        }
        if let last = words.last, words.count > 1, GrammarLexicon.uiNouns.contains(last) {
            every = every || last.hasSuffix("s")
            words.removeLast()
        }
        return lookUp(words, for: mark, every: every || isPlural(words))
    }

    private func lookUp(_ words: [String], for mark: MarkKind, every: Bool) -> ItemResult {
        let kinds = GrammarLexicon.kinds.first { Words.equal($0.words, words) }?.kinds
        let exact = lines.filter { Words.equal($0.words, words) }.map(\.target)
        // Redaction goes to values, so a kind wins over a label that happens to read "Email".
        if let kinds, mark == .blur || exact.isEmpty {
            let found = targets.filter { kinds.contains($0.kind) }
            return found.isEmpty ? .notFound(words.joined(separator: " ")) : .kinds(kinds)
        }
        if let result = choose(exact, for: mark, every: every) { return result }
        let containing = lines.filter { Words.contains($0.words, words) }.map(\.target)
        if let result = choose(containing, for: mark, every: every) { return result }
        if let near = closeMatch(words) { return .targets([near]) }
        if words.contains(where: GrammarLexicon.kindWords.contains) {
            return .decline("\"\(words.joined(separator: " "))\" describes a sensitive value the grammar cannot place")
        }
        return .unmatched(words.joined(separator: " "))
    }

    /// One mark per target for blur and highlight, or when the phrase was plural; otherwise exactly one target.
    private func choose(_ found: [Target], for mark: MarkKind, every: Bool) -> ItemResult? {
        if found.isEmpty { return nil }
        if found.count == 1 || every || mark == .blur || mark == .highlight { return .targets(found) }
        return .ambiguous(found)
    }

    /// A whole line that differs from the phrase by a mis-hearing: "prising" for "Pricing", "in voices" for
    /// "Invoices". Only a single clearly closest line counts.
    func closeMatch(_ words: [String]) -> Target? {
        let phrase = words.joined()
        guard phrase.count >= 5 else { return nil }
        let allowed = phrase.count >= 9 ? 2 : 1
        let scored = lines.map { (target: $0.target, distance: Words.distance(phrase, $0.words.joined())) }
            .filter { $0.distance <= allowed }
            .sorted { $0.distance < $1.distance }
        guard let best = scored.first else { return nil }
        return scored.filter { $0.distance == best.distance }.count == 1 ? best.target : nil
    }

    /// Whole lines that equal a run of words, longest first: "reply forward" as "Reply", then "Forward".
    /// Every word must be used, or nil.
    func segment(_ words: [String]) -> [[String]]? {
        if words.isEmpty { return [] }
        for length in stride(from: words.count, through: 1, by: -1) {
            let head = Array(words.prefix(length))
            guard lines.contains(where: { Words.equal($0.words, head) }) else { continue }
            if let rest = segment(Array(words.dropFirst(length))) { return [head] + rest }
        }
        return nil
    }

    private func isPlural(_ words: [String]) -> Bool {
        guard let last = words.last, last.count > 3, last.hasSuffix("s"), !last.hasSuffix("ss") else { return false }
        return !lines.contains { Words.equal($0.words, words) && $0.words.last == last }
    }
}
