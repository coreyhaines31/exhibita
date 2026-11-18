import ExhibitCore
import Foundation

/// What an interpreter is given: the instruction and the capture's targets, as text only.
///
/// Never the image. Sensitive targets (`email`, `key`, `card`, `phone`) arrive without `text`, and their characters
/// are already masked in the lines they came from, so no interpreter, local or hosted, ever sees a secret.
public struct InterpretRequest: Sendable, Equatable {
    /// What the person said or typed, as transcribed.
    public var instruction: String
    /// The capture's targets, in reading order.
    public var targets: [Target]
    /// Where the pointer was while the instruction was given, in pixels of the original, for "blur this".
    public var pointer: PixelPoint?

    public init(instruction: String, targets: [Target], pointer: PixelPoint? = nil) {
        self.instruction = instruction
        self.targets = targets
        self.pointer = pointer
    }
}

/// One way of naming what an operation goes on. Each resolves against the request's targets with the same meaning
/// as the CLI selector of the same name, so an interpretation can be applied by the existing `apply` machinery.
public enum TargetPick: Sendable, Equatable, Hashable, Codable {
    /// One listed target. Models only ever answer with these: they choose among the listed targets and never
    /// produce coordinates.
    case id(UUID)
    /// Every target of a kind: `--kind`.
    case kind(TargetKind)
    /// Every text line containing the string, ignoring case and look-alike letters: `--text`.
    case text(String)
}

/// One mark to draw, on everything its picks resolve to.
public struct InterpretedOperation: Sendable, Equatable, Codable {
    public var mark: MarkKind
    public var picks: [TargetPick]
    /// The words of a `text` mark, or an arrow's caption.
    public var label: String?

    public init(mark: MarkKind, picks: [TargetPick], label: String? = nil) {
        self.mark = mark
        self.picks = picks
        self.label = label
    }
}

/// What an instruction asked for, as operations, plus every part that could not be found on the screen.
public struct Interpretation: Sendable, Equatable, Codable {
    public var operations: [InterpretedOperation]
    /// Things the instruction named that are not among the targets, in the person's words: "logout button".
    /// Shown as "Couldn't find: ..."; never silently dropped.
    public var notFound: [String]

    public init(operations: [InterpretedOperation], notFound: [String] = []) {
        self.operations = operations
        self.notFound = notFound
    }
}

/// An interpreter either understands an instruction or declines it. Declining is not an error: the grammar declines
/// anything it is not sure of, so the next interpreter (a model) can try.
public enum InterpretOutcome: Sendable, Equatable {
    case understood(Interpretation)
    case declined(reason: String)

    public var interpretation: Interpretation? {
        if case .understood(let interpretation) = self { return interpretation }
        return nil
    }
}

/// Turns an instruction into operations against a target list. The grammar, the on-device model, a local model
/// endpoint and, later, a hosted service are implementations of this one interface.
public protocol Interpreter: Sendable {
    var name: String { get }
    func interpret(_ request: InterpretRequest) async throws -> InterpretOutcome
}

/// Tries each interpreter in order and returns the first that understands. This is how the free tier ships:
/// the grammar first, a model only for what the grammar declines.
public struct ChainedInterpreter: Interpreter {
    public let interpreters: [any Interpreter]

    public init(_ interpreters: [any Interpreter]) {
        self.interpreters = interpreters
    }

    public var name: String { interpreters.map(\.name).joined(separator: "+") }

    public func interpret(_ request: InterpretRequest) async throws -> InterpretOutcome {
        var reasons: [String] = []
        for interpreter in interpreters {
            let outcome = try await interpreter.interpret(request)
            if case .declined(let reason) = outcome {
                reasons.append("\(interpreter.name): \(reason)")
                continue
            }
            return outcome
        }
        return .declined(reason: reasons.joined(separator: "; "))
    }
}
