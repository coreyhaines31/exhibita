import ArgumentParser
import ExhibitCore
import ExhibitInterpret
import Foundation

/// What `say` reads from outside its arguments: the environment and how it reaches a model. Tests replace both.
struct CLIContext: Sendable {
    var environment: [String: String]
    var transport: any ModelTransport

    @TaskLocal static var current = CLIContext(environment: ProcessInfo.processInfo.environment,
                                               transport: URLSessionModelTransport())
}

struct ModelOptions: ParsableArguments {
    static let modelVariable = "EXHIBIT_MODEL"
    static let endpointVariable = "EXHIBIT_MODEL_ENDPOINT"
    static let apiVariable = "EXHIBIT_MODEL_API"
    static let timeoutVariable = "EXHIBIT_MODEL_TIMEOUT"

    @Option(name: .customLong("model"), help: ArgumentHelp(
        "A local model for what the grammar cannot read, like qwen3:8b. Default: $EXHIBIT_MODEL. Without one, "
        + "only the grammar is used.", valueName: "name"))
    var model: String?

    @Option(help: ArgumentHelp(
        "The model server, on this Mac only (localhost, 127.0.0.1 or ::1). Default: $EXHIBIT_MODEL_ENDPOINT, "
        + "else Ollama at http://127.0.0.1:11434. A URL with /v1 is OpenAI-compatible (LM Studio, llama.cpp).",
        valueName: "url"))
    var modelEndpoint: String?

    @Option(help: ArgumentHelp("ollama or openai. Default: $EXHIBIT_MODEL_API, else from the endpoint URL.",
                               valueName: "api"))
    var modelApi: String?

    @Option(help: ArgumentHelp("Seconds to wait for the model, loading included. Default: $EXHIBIT_MODEL_TIMEOUT, "
                               + "else 60.", valueName: "seconds"))
    var modelTimeout: Double?

    @Flag(help: "Use the grammar only, even when a model is configured.")
    var noModel = false

    /// The configured model, or nil when there is none. Flags win over environment variables.
    func endpoint(environment: [String: String]) throws -> ModelEndpoint? {
        func value(_ flag: String?, _ variable: String) -> String? {
            let raw = flag ?? environment[variable]
            return raw.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
        }
        guard !noModel else { return nil }
        let url = value(modelEndpoint, Self.endpointVariable)
        guard let name = value(model, Self.modelVariable) else {
            if url != nil {
                throw CLIError.usage("A model endpoint is set but no model name. Pass --model <name> or set "
                                     + "\(Self.modelVariable).")
            }
            return nil
        }
        let api = try Self.api(value(modelApi, Self.apiVariable))
        let timeout = try Self.timeout(value(modelTimeout.map { String($0) }, Self.timeoutVariable))
        let endpointURL = try url.map { raw in
            guard let parsed = URL(string: raw) else { throw CLIError.usage("\"\(raw)\" is not a URL.") }
            return parsed
        } ?? ModelEndpoint.defaultURL
        do {
            return try ModelEndpoint(url: endpointURL, model: name, api: api, timeout: timeout)
        } catch let error as ModelError {
            if case .notLoopback = error {
                throw CLIError(code: "endpoint_not_loopback", message: error.description, status: .usage)
            }
            throw CLIError.usage(error.description)
        }
    }

    private static func api(_ raw: String?) throws -> ModelEndpoint.API? {
        guard let raw else { return nil }
        guard let api = ModelEndpoint.API(rawValue: raw.lowercased()) else {
            throw CLIError.usage("Unknown model API \"\(raw)\". Use ollama or openai.")
        }
        return api
    }

    private static func timeout(_ raw: String?) throws -> TimeInterval {
        guard let raw else { return ModelEndpoint.defaultTimeout }
        guard let seconds = Double(raw), seconds > 0, seconds.isFinite else {
            throw CLIError.usage("The model timeout must be a positive number of seconds, not \"\(raw)\".")
        }
        return seconds
    }
}

struct Say: ExhibitCommand {
    static let configuration = CommandConfiguration(
        abstract: "Mark up an image from an instruction in plain words.",
        discussion: """
            The built-in grammar reads instructions like "blur the emails and circle pricing" with no model. When \
            it cannot, and a local model is configured (--model, or $EXHIBIT_MODEL), the model reads it from the \
            text on the screen, never the image. Without a model, such an instruction exits 5 with "needs_model" \
            and changes nothing. Marks for what was found are applied and what was not found is listed.
            Example: exhibit say shot.png "blur the emails and circle pricing"
            """
    )

    @Argument(help: ArgumentHelp("A PNG or JPEG file, or a .exhibit bundle.", valueName: "input")) var input: String
    @Argument(help: ArgumentHelp("What to do, in plain words.", valueName: "instruction")) var instruction: String
    @Option(help: ArgumentHelp("Where the pointer is, in pixels, for \"this\" and \"here\".", valueName: "x,y"))
    var pointer: String?
    @OptionGroup(title: "Model") var modelOptions: ModelOptions
    @OptionGroup(title: "Output") var outputOptions: OutputOptions

    func execute() throws -> String {
        let instruction = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !instruction.isEmpty else { throw CLIError.usage("say needs an instruction, like \"blur the emails\".") }
        let pointer = try pointer.map { try Parse.point($0, option: "--pointer") }
        let context = CLIContext.current
        let endpoint = try modelOptions.endpoint(environment: context.environment)

        var session = try Session.open(input)
        let outputURL = try session.outputURL(requested: outputOptions.output, force: outputOptions.force)
        try session.loadTargets()
        let request = InterpretRequest(instruction: instruction, targets: session.targets, pointer: pointer)

        let (interpretation, interpreter) = try Self.interpret(request, endpoint: endpoint,
                                                               transport: context.transport)
        let summary = SaySummary(interpretation: interpretation, targets: session.targets)
        guard !interpretation.operations.isEmpty else {
            if interpretation.notFound.isEmpty {
                throw CLIError(code: "not_understood", message: "\"\(instruction)\" was not understood. No changes made.",
                               status: .noMatch)
            }
            var error = CLIError(code: "no_match", message: summary.sentence + " No changes made.", status: .noMatch)
            error.notFound = interpretation.notFound
            error.hint = "Run `exhibit targets <input>` to see the text that was read from the image."
            throw error
        }

        let specs = Self.specs(for: interpretation)
        let (placed, reports) = try MarkRun.plan(specs, in: session, indexed: true)
        try session.write(placed.map(\.mark), to: outputURL)
        let base = MarkOutput(session: session, output: outputURL, placed: placed, reports: reports)
        return OutputJSON.string(SayOutput(base: base, instruction: instruction, interpreter: interpreter,
                                           model: interpreter == "model" ? endpoint?.model : nil, summary: summary,
                                           notFound: interpretation.notFound))
    }

    /// The grammar first; the model only when the grammar declines and one is configured.
    static func interpret(_ request: InterpretRequest, endpoint: ModelEndpoint?, transport: any ModelTransport) throws
        -> (Interpretation, String) {
        let reason: String
        switch GrammarInterpreter.interpret(request) {
        case .understood(let interpretation): return (interpretation, "grammar")
        case .declined(let why): reason = why
        }
        guard let endpoint else {
            throw CLIError(code: "needs_model",
                           message: "The built-in grammar could not read this instruction (\(reason)), and no model "
                               + "is set up. No changes made. Rephrase it with a verb and the words on the screen, "
                               + "like \"blur the emails\" or \"circle Pricing\", or set up a local model: pass "
                               + "--model <name> or set \(ModelOptions.modelVariable) (Ollama at "
                               + "http://127.0.0.1:11434 by default; see docs/cli.md).",
                           status: .needsModel)
        }
        do {
            let outcome = try ModelInterpreter(endpoint: endpoint, transport: transport).interpretNow(request)
            guard let interpretation = outcome.interpretation else {
                throw CLIError(code: "not_understood", message: "The model declined the instruction. No changes made.",
                               status: .noMatch)
            }
            return (interpretation, "model")
        } catch let error as ModelError {
            throw CLIError(code: "model_failed", message: error.description + " No changes made.",
                           status: .modelFailed)
        }
    }

    /// One spec per operation, naming targets by id so marks stay attached to them in a bundle. Steps get one spec
    /// per target, so they are numbered in the order said rather than in reading order.
    static func specs(for interpretation: Interpretation) -> [MarkSpec] {
        interpretation.operations.flatMap { operation -> [MarkSpec] in
            let selectors = operation.picks.map { pick -> Selector in
                switch pick {
                case .id(let id): .target(id)
                case .kind(let kind): .kind(kind)
                case .text(let text): .text(text)
                }
            }
            var spec = MarkSpec(kind: operation.mark)
            spec.label = operation.label
            spec.all = true
            spec.allowMissing = true
            if operation.mark == .step {
                return selectors.map { selector in
                    var single = spec
                    single.selectors = [selector]
                    return single
                }
            }
            spec.selectors = selectors
            return [spec]
        }
    }
}

/// `say`'s JSON: everything a mark command prints, plus who answered, what was done and what was not found.
struct SayOutput: Encodable {
    var base: MarkOutput
    var instruction: String
    /// "grammar" or "model".
    var interpreter: String
    var model: String?
    var summary: SaySummary
    var notFound: [String]

    private enum Keys: String, CodingKey {
        case instruction, interpreter, model, summary, operations, notFound, complete
    }

    func encode(to encoder: Encoder) throws {
        try base.encode(to: encoder)
        var container = encoder.container(keyedBy: Keys.self)
        try container.encode(instruction, forKey: .instruction)
        try container.encode(interpreter, forKey: .interpreter)
        try container.encodeIfPresent(model, forKey: .model)
        try container.encode(summary.sentence, forKey: .summary)
        try container.encode(summary.operations, forKey: .operations)
        try container.encode(notFound, forKey: .notFound)
        try container.encode(notFound.isEmpty, forKey: .complete)
    }
}
