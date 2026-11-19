import Foundation

/// The one line Settings shows about the model in use: what is used, or what is wrong and how to fix it, with the
/// command to copy when there is one.
public enum ModelStatus: Equatable, Sendable {
    /// Discovery has not answered yet.
    case checking
    /// A found model is in use; `isDefault` when the person never chose and it was picked for them.
    case using(model: String, server: ModelServer.Kind, isDefault: Bool)
    /// The typed Other endpoint is in use; Test checks that it answers.
    case usingOther(model: String, endpoint: String)
    /// The person chose built-in commands only.
    case builtInOnly
    /// No server answered and nothing was chosen.
    case noServer
    /// A server answered with no models.
    case noModels(ModelServer.Kind)
    /// The chosen model is no longer on its server.
    case chosenMissing(model: String, server: ModelServer.Kind)
    /// The chosen model's server is not answering.
    case serverDown(ModelServer.Kind, model: String)
    /// Something answered at a server's address, but not with a list of models.
    case badAnswer(ModelServer.Kind)
    /// Other is chosen but no model name is typed.
    case otherIncomplete
    /// Other's endpoint can't be used (not this Mac, not a URL).
    case otherInvalid(String)

    public var isProblem: Bool {
        switch self {
        case .checking, .using, .usingOther, .builtInOnly: false
        case .noServer, .noModels, .chosenMissing, .serverDown, .badAnswer, .otherIncomplete, .otherInvalid: true
        }
    }

    /// The command that fixes it, to copy into Terminal.
    public var command: String? {
        switch self {
        case .noServer, .noModels(.ollama): "ollama pull \(RecommendedModels.preferred)"
        case .chosenMissing(let model, .ollama): "ollama pull \(model)"
        case .serverDown(.ollama, _): "ollama serve"
        default: nil
        }
    }

    public var message: String {
        switch self {
        case .checking:
            "Looking for a model server on this Mac…"
        case let .using(model, server, _):
            "Using \(model) from \(server.name) on this Mac."
        case let .usingOther(model, endpoint):
            "Using \(model) at \(endpoint). Test checks that it answers."
        case .builtInOnly:
            "Built-in commands only. An instruction they can't read says so in the editor."
        case .noServer:
            "No model server is running on this Mac. Install Ollama from ollama.com and open it, then get the "
                + "recommended model:"
        case .noModels(.ollama):
            "Ollama is running but has no models. Get the recommended one:"
        case .noModels(.openAICompatible):
            "LM Studio is running but has no model loaded. Load one in LM Studio, then Check Again."
        case let .chosenMissing(model, .ollama):
            "\(model) is no longer in Ollama. Pick another model, or get it back:"
        case let .chosenMissing(model, .openAICompatible):
            "\(model) is no longer loaded in LM Studio. Pick another model, or load it in LM Studio."
        case let .serverDown(.ollama, model):
            "Ollama isn't answering, so \(model) can't be used. Open Ollama, or start it:"
        case let .serverDown(.openAICompatible, model):
            "LM Studio's server isn't answering, so \(model) can't be used. Start the server in LM Studio, then "
                + "Check Again."
        case .badAnswer(let kind):
            "Something answered at \(Self.address(kind)), but not with a list of models. Quit whatever else uses that "
                + "port, or choose Other."
        case .otherIncomplete:
            "Type the model's name as the server knows it."
        case .otherInvalid(let detail):
            detail
        }
    }

    static func address(_ kind: ModelServer.Kind) -> String {
        guard let url = ModelDiscovery.candidates.first(where: { $0.kind == kind })?.url, let host = url.host else {
            return "this Mac"
        }
        return url.port.map { "\(host):\($0)" } ?? host
    }
}
