import Foundation

/// A model server on this Mac and the models it has.
public struct ModelServer: Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        /// Ollama's own API, `GET /api/tags`.
        case ollama
        /// LM Studio, llama.cpp or any other OpenAI-compatible server, `GET /v1/models`.
        case openAICompatible
    }

    public var kind: Kind
    /// The base URL a `ModelEndpoint` takes: `http://127.0.0.1:11434` or `http://127.0.0.1:1234/v1`.
    public var url: URL
    /// The models as the server names them, in its order.
    public var models: [String]

    public init(kind: Kind, url: URL, models: [String]) {
        self.kind = kind
        self.url = url
        self.models = models
    }

    /// What a person calls it.
    public var name: String { kind.name }
}

extension ModelServer.Kind {
    public var name: String {
        switch self {
        case .ollama: "Ollama"
        case .openAICompatible: "LM Studio"
        }
    }

    /// The API a `ModelEndpoint` for this server speaks.
    public var api: ModelEndpoint.API {
        switch self {
        case .ollama: .ollama
        case .openAICompatible: .openai
        }
    }
}

/// What asking one address for its models found.
public enum ServerProbe: Equatable, Sendable {
    /// It answered with at least one model.
    case found(ModelServer)
    /// It answered, with no models.
    case noModels(ModelServer)
    /// Nothing answered there, or not in time.
    case notRunning(ModelServer.Kind, URL)
    /// Something answered, but not with a model list.
    case badAnswer(ModelServer.Kind, URL, String)
    /// The address is not this Mac, so nothing was sent.
    case notLoopback(ModelServer.Kind, URL)

    public var kind: ModelServer.Kind {
        switch self {
        case .found(let server), .noModels(let server): server.kind
        case .notRunning(let kind, _), .badAnswer(let kind, _, _), .notLoopback(let kind, _): kind
        }
    }

    public var server: ModelServer? {
        if case .found(let server) = self { return server }
        return nil
    }
}

/// Everything one discovery found, in the order the servers are asked.
public struct Discovery: Equatable, Sendable {
    public var probes: [ServerProbe]

    public init(probes: [ServerProbe]) {
        self.probes = probes
    }

    /// The servers that have models.
    public var servers: [ModelServer] { probes.compactMap(\.server) }

    /// What was found for one kind of server.
    public func probe(for kind: ModelServer.Kind) -> ServerProbe? {
        probes.first { $0.kind == kind }
    }

    /// The model used when the person has never chosen one (`RecommendedModels.pick`).
    public var defaultChoice: (server: ModelServer, model: String)? { RecommendedModels.pick(from: servers) }
}

/// Which installed model to use when the person has never chosen.
public enum RecommendedModels {
    /// Best first. From the interpreter eval: `qwen3.8:27b` scored best on held-out instructions
    /// (`docs/product/spike-interpreter.md`, `docs/product/heldout2-results.md`); `ornith-1.5:9b` is the fast option
    /// (`docs/product/model-latency.md`). Change this list only with a new eval run.
    public static let ordered = ["qwen3.8:27b", "ornith-1.5:9b"]

    /// The first recommended model any server has, servers in the order asked; else the first server's first
    /// model; nil when no server has a model.
    public static func pick(from servers: [ModelServer]) -> (server: ModelServer, model: String)? {
        for model in ordered {
            if let server = servers.first(where: { $0.models.contains(model) }) { return (server, model) }
        }
        guard let server = servers.first(where: { !$0.models.isEmpty }), let model = server.models.first else {
            return nil
        }
        return (server, model)
    }

    public static var preferred: String { ordered[0] }
}

/// Finds the model servers on this Mac: Ollama at `127.0.0.1:11434` and an OpenAI-compatible server (LM Studio's
/// default) at `127.0.0.1:1234/v1`, both asked at once with a short timeout. Loopback addresses only: anything
/// else is refused before `fetch` is called. Only the list of model names is asked for; no screen text is sent.
public enum ModelDiscovery {
    /// A `GET` of a URL, as `URLSessionModelTransport.get` does it. Throws when nothing answers.
    public typealias Fetch = @Sendable (URL, TimeInterval) throws -> ModelHTTPResponse

    public static let timeout: TimeInterval = 1

    /// The addresses asked, in order.
    public static let candidates: [(kind: ModelServer.Kind, url: URL)] = [
        (.ollama, URL(string: "http://127.0.0.1:11434")!),
        (.openAICompatible, URL(string: "http://127.0.0.1:1234/v1")!)
    ]

    /// Asks every candidate in parallel, off the caller's thread.
    public static func discover(candidates: [(kind: ModelServer.Kind, url: URL)] = candidates,
                                timeout: TimeInterval = timeout, fetch: @escaping Fetch) async -> Discovery {
        let probes = await withTaskGroup(of: (Int, ServerProbe).self) { group in
            for (index, candidate) in candidates.enumerated() {
                group.addTask {
                    (index, probe(candidate.kind, at: candidate.url, timeout: timeout, fetch: fetch))
                }
            }
            var probes: [(Int, ServerProbe)] = []
            for await probe in group { probes.append(probe) }
            return probes.sorted { $0.0 < $1.0 }.map(\.1)
        }
        return Discovery(probes: probes)
    }

    /// One server, blocking.
    public static func probe(_ kind: ModelServer.Kind, at url: URL, timeout: TimeInterval = timeout,
                             fetch: Fetch) -> ServerProbe {
        guard let host = url.host, ModelEndpoint.isLoopback(host) else { return .notLoopback(kind, url) }
        let listURL = switch kind {
        case .ollama: url.appendingPathComponent("api/tags")
        case .openAICompatible: url.appendingPathComponent("models")
        }
        let reply: ModelHTTPResponse
        do {
            reply = try fetch(listURL, timeout)
        } catch {
            return .notRunning(kind, url)
        }
        guard reply.status == 200 else {
            return .badAnswer(kind, url, "HTTP \(reply.status)")
        }
        guard let models = models(kind, in: reply.body) else {
            return .badAnswer(kind, url, "not a model list")
        }
        let server = ModelServer(kind: kind, url: url, models: models)
        return models.isEmpty ? .noModels(server) : .found(server)
    }

    /// The model names in a list reply, or nil when it is not one: Ollama's `{"models": [{"name": ...}]}`, an
    /// OpenAI-compatible `{"data": [{"id": ...}]}`.
    static func models(_ kind: ModelServer.Kind, in data: Data) -> [String]? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let (key, field) = kind == .ollama ? ("models", "name") : ("data", "id")
        guard let entries = object[key] as? [[String: Any]] else { return nil }
        return entries.compactMap { $0[field] as? String }.filter { !$0.isEmpty }
    }
}
