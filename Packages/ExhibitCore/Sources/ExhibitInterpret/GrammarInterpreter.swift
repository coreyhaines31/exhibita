import ExhibitCore
import Foundation

/// The free interpreter with no model: a fixed grammar of verbs, kinds, pointer words and on-screen text.
///
/// It handles "blur the emails", "circle Pricing and point at Sign up", "highlight this" (with the pointer), steps
/// and labels, and close mis-hearings of on-screen words. Anything that needs judgement ("hide anything that
/// identifies the customer"), any phrase it cannot find, and any choice between several equal matches, it declines
/// rather than guesses, so a model can try next. It reports a kind the screen has none of ("blur the faces") as not
/// found.
public struct GrammarInterpreter: Interpreter {
    public init() {}

    public var name: String { "grammar" }

    public func interpret(_ request: InterpretRequest) async throws -> InterpretOutcome {
        Self.interpret(request)
    }

    public static func interpret(_ request: InterpretRequest) -> InterpretOutcome {
        let words = Words.of(request.instruction)
        if let reason = GrammarClauses.judgement(in: words) { return .declined(reason: reason) }
        guard let clauses = GrammarClauses.split(words) else {
            return .declined(reason: "no known verb at the start")
        }
        var parser = GrammarParser(matcher: GrammarMatcher(request: request))
        for clause in clauses {
            if let reason = parser.add(clause) { return .declined(reason: reason) }
        }
        guard !parser.operations.isEmpty || !parser.notFound.isEmpty else {
            return .declined(reason: "nothing to do")
        }
        return .understood(Interpretation(operations: parser.operations, notFound: parser.notFound))
    }
}

/// One verb and the words after it.
struct GrammarClause: Equatable {
    var verb: [String]
    var mark: MarkKind
    var rest: [String]
}

enum GrammarClauses {
    /// The clauses of an instruction, split at "and", "then" and the like when a verb follows. Nil when it does not
    /// start with a verb.
    static func split(_ words: [String]) -> [GrammarClause]? {
        var words = words
        while let first = words.first, GrammarLexicon.fillers.contains(first), verb(at: 0, in: words) == nil {
            words.removeFirst()
        }
        guard let first = verb(at: 0, in: words) else { return nil }
        var clauses = [GrammarClause(verb: Array(words.prefix(first.length)), mark: first.mark, rest: [])]
        var index = first.length
        while index < words.count {
            if GrammarLexicon.conjunctions.contains(words[index]), let next = verb(at: index + 1, in: words) {
                clauses.append(GrammarClause(verb: Array(words[(index + 1)..<(index + 1 + next.length)]),
                                             mark: next.mark, rest: []))
                index += 1 + next.length
                continue
            }
            clauses[clauses.count - 1].rest.append(words[index])
            index += 1
        }
        return clauses
    }

    static func verb(at index: Int, in words: [String]) -> (mark: MarkKind, length: Int)? {
        for entry in GrammarLexicon.verbs where index + entry.words.count <= words.count {
            if Array(words[index..<(index + entry.words.count)]) == entry.words {
                return (entry.mark, entry.words.count)
            }
        }
        return nil
    }

    /// Why the instruction needs judgement, or nil. A relative word ("the commit that fixed ...") counts unless it
    /// ends its clause, as in "highlight that".
    static func judgement(in words: [String]) -> String? {
        if let word = words.first(where: GrammarLexicon.judgement.contains) {
            return "\"\(word)\" needs judgement"
        }
        for (index, word) in words.enumerated() where GrammarLexicon.relatives.contains(word) {
            let next = index + 1 < words.count ? words[index + 1] : nil
            let afterNext = index + 2 < words.count ? words[index + 2] : nil
            let endsClause = next == nil || GrammarLexicon.conjunctions.contains(next ?? "")
                || (next == "one" && (afterNext == nil || GrammarLexicon.conjunctions.contains(afterNext ?? "")))
            if !endsClause { return "\"\(word) ...\" describes something rather than naming it" }
        }
        return nil
    }
}
