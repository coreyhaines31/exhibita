import Foundation

/// Why a mark could not be planned. The CLI turns it into its JSON error and exit code (`docs/cli.md`); the editor
/// shows the message.
public struct PlanError: Error, Equatable, Sendable, CustomStringConvertible {
    public enum Code: String, Sendable {
        case usage
        case noMatch = "no_match"
        case ambiguous
        case nthOutOfRange = "nth_out_of_range"
    }

    public var code: Code
    public var message: String
    /// Selectors that matched nothing, or the one that was ambiguous, as typed.
    public var selectors: [String]?
    /// For ambiguous and out-of-range errors: what the selector matched.
    public var candidates: [Candidate]?
    /// The selectors that matched nothing, for the CLI's hint.
    public var missing: [MarkSelector] = []

    public init(code: Code, message: String, selectors: [String]? = nil, candidates: [Candidate]? = nil,
                missing: [MarkSelector] = []) {
        self.code = code
        self.message = message
        self.selectors = selectors
        self.candidates = candidates
        self.missing = missing
    }

    public static func usage(_ message: String) -> PlanError {
        PlanError(code: .usage, message: message)
    }

    /// Prefixes the message with where in `marks.json` the problem is.
    public func inEntry(_ index: Int?) -> PlanError {
        guard let index else { return self }
        var copy = self
        copy.message = "marks[\(index)]: \(message)"
        return copy
    }

    public var description: String { message }
}
