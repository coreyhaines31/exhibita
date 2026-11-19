import Foundation

/// The app's setting for instructions in the person's own words: which local model, if any, reads what the
/// built-in commands can't. Never chosen means the recommended installed model; `.none` means built-in commands
/// only. Stored as it was typed, and turned into a `ModelEndpoint` only when used, so a bad value is reported,
/// never sent.
public struct ModelSettings: Codable, Equatable, Sendable {
    public enum APIChoice: String, Codable, CaseIterable, Sendable {
        /// From the URL: a path with `/v1` is OpenAI-compatible, anything else Ollama.
        case automatic
        case ollama
        case openai

        public var api: ModelEndpoint.API? {
            switch self {
            case .automatic: nil
            case .ollama: .ollama
            case .openai: .openai
            }
        }

        public var title: String {
            switch self {
            case .automatic: "Automatic"
            case .ollama: "Ollama"
            case .openai: "OpenAI-compatible"
            }
        }
    }

    /// What the person picked in Settings. Nil until they pick, which is not the same as `.none`.
    public enum Choice: Codable, Equatable, Sendable {
        /// Built-in commands only, no model.
        case none
        /// A model a found server listed.
        case installed(server: ModelServer.Kind, url: String, model: String)
        /// The typed `endpoint`, `model` and `api`.
        case other
    }

    /// The typed fields' switch from before there was a choice; read only to keep an old setting (`effectiveChoice`).
    public var enabled: Bool
    public var endpoint: String
    public var model: String
    public var api: APIChoice
    /// Nil when the person has never chosen: then the recommended installed model is used (`Discovery.defaultChoice`).
    public var choice: Choice?

    public static let defaultEndpoint = ModelEndpoint.defaultURL.absoluteString

    public init(enabled: Bool = false, endpoint: String = Self.defaultEndpoint, model: String = "",
                api: APIChoice = .automatic, choice: Choice? = nil) {
        self.enabled = enabled
        self.endpoint = endpoint
        self.model = model
        self.api = api
        self.choice = choice
    }

    /// The choice in effect: a setting saved before there was a choice that had a model turned on counts as Other.
    public var effectiveChoice: Choice? {
        if let choice { return choice }
        return enabled && !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .other : nil
    }

    /// The model the editor uses, given what discovery found (nil before it has run). An explicit choice is used as
    /// chosen, found or not, so a problem shows as the model's own error; never chosen means the default, if any
    /// server has a model. Throws for an Other endpoint that is not this Mac or not usable.
    public func endpoint(discovery: Discovery?) throws -> ModelEndpoint? {
        switch effectiveChoice {
        case .none?:
            return nil
        case let .installed(server, url, model)?:
            guard let url = URL(string: url) else { throw ModelError.invalidEndpoint("\"\(url)\" is not a URL") }
            return try ModelEndpoint(url: url, model: model, api: server.api)
        case .other?:
            guard !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return try configuredEndpoint()
        case nil:
            guard let picked = discovery?.defaultChoice else { return nil }
            return try ModelEndpoint(url: picked.server.url, model: picked.model, api: picked.server.kind.api)
        }
    }

    /// The one line Settings shows under the picker.
    public func status(discovery: Discovery?) -> ModelStatus {
        switch effectiveChoice {
        case .none?: .builtInOnly
        case .other?: otherStatus()
        case let .installed(server, _, model)?: discovery.map { Self.status(of: model, on: server, in: $0) } ?? .checking
        case nil: discovery.map(Self.defaultStatus) ?? .checking
        }
    }

    private func otherStatus() -> ModelStatus {
        guard !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .otherIncomplete }
        do {
            let endpoint = try configuredEndpoint()
            return .usingOther(model: endpoint.model, endpoint: endpoint.url.absoluteString)
        } catch {
            return .otherInvalid((error as? ModelError)?.description ?? error.localizedDescription)
        }
    }

    private static func status(of model: String, on server: ModelServer.Kind, in discovery: Discovery) -> ModelStatus {
        switch discovery.probe(for: server) {
        case .found(let found)? where found.models.contains(model): .using(model: model, server: server, isDefault: false)
        case .found?: .chosenMissing(model: model, server: server)
        case .noModels?: .chosenMissing(model: model, server: server)
        case .notRunning?, .notLoopback?: .serverDown(server, model: model)
        case .badAnswer?: .badAnswer(server)
        case nil: .using(model: model, server: server, isDefault: false)
        }
    }

    /// Never chosen: the default in use, or why there is none, most useful first.
    private static func defaultStatus(_ discovery: Discovery) -> ModelStatus {
        if let picked = discovery.defaultChoice {
            return .using(model: picked.model, server: picked.server.kind, isDefault: true)
        }
        for probe in discovery.probes {
            if case .noModels(let server) = probe { return .noModels(server.kind) }
        }
        for probe in discovery.probes {
            if case .badAnswer(let kind, _, _) = probe { return .badAnswer(kind) }
        }
        return .noServer
    }

    /// The endpoint to use, or nil when free-form instructions are off or no model is named. Throws
    /// `ModelError.notLoopback` for any host that is not this Mac and `.invalidEndpoint` for anything unusable.
    public func modelEndpoint() throws -> ModelEndpoint? {
        guard enabled, !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return try configuredEndpoint()
    }

    /// The endpoint as configured, on or off, for the Test button.
    public func configuredEndpoint() throws -> ModelEndpoint {
        let raw = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: raw.isEmpty ? Self.defaultEndpoint : raw) else {
            throw ModelError.invalidEndpoint("\"\(raw)\" is not a URL")
        }
        return try ModelEndpoint(url: url, model: model, api: api.api)
    }
}

/// What the Test button found.
public enum ModelProbeResult: Equatable, Sendable {
    /// The model answered; seconds include loading it, if it was not loaded.
    case reachable(model: String, seconds: Double)
    /// The server answered but has no model by that name.
    case modelMissing(String)
    /// The endpoint is not on this Mac; nothing was sent.
    case notLoopback(String)
    /// Nothing answered at the endpoint.
    case unreachable(String)
    /// Anything else: a bad URL, an empty model name, an unexpected reply.
    case failed(String)

    public var isReachable: Bool {
        if case .reachable = self { return true }
        return false
    }

    public var message: String {
        switch self {
        case let .reachable(model, seconds):
            "Reachable. \(model) answered in \(String(format: "%.1f", seconds)) s, loading included if it wasn't loaded."
        case .modelMissing(let model):
            "The server is running but has no model called \u{201C}\(model)\u{201D}. Check the name, or install it "
                + "with your model runner (for Ollama, ollama pull \(model))."
        case .notLoopback(let host):
            "\(host) isn't this Mac. Only localhost, 127.0.0.1 or ::1 are allowed, so nothing was sent."
        case .unreachable(let url):
            "Nothing is answering at \(url). Is the model server running?"
        case .failed(let detail):
            detail
        }
    }
}

/// Sends one tiny chat request to check an endpoint: the same path and body shape `ModelInterpreter` uses, a
/// one-word answer, no screen text.
public enum ModelProbe {
    public static func run(_ settings: ModelSettings, transport: any ModelTransport = URLSessionModelTransport(),
                           now: () -> Date = Date.init) -> ModelProbeResult {
        let endpoint: ModelEndpoint
        do {
            endpoint = try settings.configuredEndpoint()
        } catch ModelError.notLoopback(let host) {
            return .notLoopback(host)
        } catch {
            return .failed((error as? ModelError)?.description ?? error.localizedDescription)
        }
        let start = now()
        do {
            let body = try endpoint.body(system: "Answer with the single word OK.", user: "Are you there?")
            let reply = try transport.post(endpoint.chatURL, body: body, timeout: endpoint.timeout)
            let seconds = now().timeIntervalSince(start)
            if reply.status == 200 { return .reachable(model: endpoint.model, seconds: seconds) }
            let text = String(bytes: reply.body, encoding: .utf8)?.lowercased() ?? ""
            if reply.status == 404 || text.contains("not found") || text.contains("does not exist") {
                return .modelMissing(endpoint.model)
            }
            return .failed("The server answered HTTP \(reply.status): \(ModelEndpoint.preview(reply.body))")
        } catch ModelError.notLoopback(let host) {
            return .notLoopback(host)
        } catch ModelError.unreachable {
            return .unreachable(endpoint.url.absoluteString)
        } catch {
            return .failed((error as? ModelError)?.description ?? error.localizedDescription)
        }
    }
}
