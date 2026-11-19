import Foundation

/// No model turned out to be available when one was needed: the person never chose one and none was found.
public struct ModelUnavailable: Error, Equatable, Sendable {
    public init() {}
}

/// The model step of the chain, resolved only when it is asked: the grammar answers first and never waits on it.
/// The app's resolver looks for a model server on this Mac (`ModelDiscovery`) only then, and returns nil when
/// there is none, which this reports as `ModelUnavailable`.
public struct LazyModelInterpreter: Interpreter {
    public typealias Resolve = @Sendable () async -> (any Interpreter)?

    private let resolve: Resolve

    public init(resolve: @escaping Resolve) {
        self.resolve = resolve
    }

    public var name: String { "model" }

    public func interpret(_ request: InterpretRequest) async throws -> InterpretOutcome {
        guard let model = await resolve() else { throw ModelUnavailable() }
        return try await model.interpret(request)
    }
}
