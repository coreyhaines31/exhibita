import Foundation

/// A local model the person runs: an Ollama server or any OpenAI-compatible server (LM Studio, llama.cpp,
/// Ollama's own `/v1`), on this Mac only.
///
/// The host must be a loopback address. Free means on-device or a model the person runs (spec decision 4), and
/// screen text never leaves the Mac, so any other host is refused before anything is sent.
public struct ModelEndpoint: Sendable, Equatable {
    public enum API: String, Sendable, CaseIterable {
        /// `POST /api/chat`, Ollama's own API.
        case ollama
        /// `POST /v1/chat/completions`.
        case openai
    }

    /// Ollama's default address.
    public static let defaultURL = URL(string: "http://127.0.0.1:11434")!
    public static let defaultTimeout: TimeInterval = 60

    /// The server's base URL, or the full chat URL.
    public let url: URL
    public let model: String
    public let api: API
    /// The longest one interpretation may take, loading the model included.
    public let timeout: TimeInterval

    /// Fails with `ModelError.notLoopback` for any host that is not this Mac, and `ModelError.invalidEndpoint` for
    /// a URL that is not http or https or a model name that is empty. With no `api`, a URL whose path has `/v1`
    /// is OpenAI-compatible and anything else is Ollama.
    public init(url: URL = Self.defaultURL, model: String, api: API? = nil,
                timeout: TimeInterval = Self.defaultTimeout) throws {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https", let host = url.host,
              !host.isEmpty else {
            throw ModelError.invalidEndpoint("\(url.absoluteString) is not an http or https URL with a host")
        }
        guard Self.isLoopback(host) else { throw ModelError.notLoopback(host) }
        let model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else { throw ModelError.invalidEndpoint("the model name is empty") }
        guard timeout > 0, timeout.isFinite else { throw ModelError.invalidEndpoint("the timeout must be positive") }
        self.url = url
        self.model = model
        self.api = api ?? (url.path.contains("/v1") ? .openai : .ollama)
        self.timeout = timeout
    }

    /// Whether a host is this Mac: `localhost`, `127.0.0.0/8` or `::1`. Names other than `localhost` are refused
    /// even if they would resolve to this Mac, so a changed DNS answer cannot send screen text elsewhere.
    public static func isLoopback(_ host: String) -> Bool {
        var host = host.lowercased()
        if host.hasPrefix("["), host.hasSuffix("]") { host = String(host.dropFirst().dropLast()) }
        if host == "localhost" || host == "::1" || host == "0:0:0:0:0:0:0:1" { return true }
        let octets = host.split(separator: ".", omittingEmptySubsequences: false)
        guard octets.count == 4, octets[0] == "127" else { return false }
        return octets.allSatisfy { octet in
            !octet.isEmpty && octet.count <= 3 && octet.allSatisfy(\.isASCII) && octet.allSatisfy(\.isNumber)
                && Int(octet).map { $0 <= 255 } == true
        }
    }

    /// Where chat requests go. A URL that already names the chat path is used as it is.
    public var chatURL: URL {
        let path = url.path
        switch api {
        case .ollama:
            if path.hasSuffix("/api/chat") { return url }
            return url.appendingPathComponent("api/chat")
        case .openai:
            if path.hasSuffix("/chat/completions") { return url }
            if path.contains("/v1") { return url.appendingPathComponent("chat/completions") }
            return url.appendingPathComponent("v1/chat/completions")
        }
    }

    /// The request body: the system prompt and the user message, greedy decoding, a capped answer. No `format` or
    /// `response_format`: some runners refuse structured output, so it is never asked for.
    func body(system: String, user: String) throws -> Data {
        let messages = [["role": "system", "content": system], ["role": "user", "content": user]]
        let object: [String: Any] = switch api {
        case .ollama:
            [
                "model": model, "stream": false, "think": false, "messages": messages,
                "options": ["temperature": 0, "seed": 1, "num_predict": ModelPrompt.maxResponseTokens]
            ]
        case .openai:
            [
                "model": model, "stream": false, "messages": messages, "temperature": 0, "seed": 1,
                "max_tokens": ModelPrompt.maxResponseTokens
            ]
        }
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    /// The text of the model's reply.
    func content(of data: Data) throws -> String {
        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let content: String? = switch api {
        case .ollama:
            (object?["message"] as? [String: Any])?["content"] as? String
        case .openai:
            ((object?["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any])?["content"] as? String
        }
        guard let content else {
            throw ModelError.badAnswer("the server's reply has no message: \(Self.preview(data))")
        }
        return content
    }

    static func preview(_ data: Data) -> String {
        String(bytes: data.prefix(300), encoding: .utf8) ?? "\(data.count) bytes"
    }
}

/// Why a model could not interpret an instruction. Never a decline: the model was asked and failed.
public enum ModelError: Error, Equatable, Sendable, CustomStringConvertible {
    case notLoopback(String)
    case invalidEndpoint(String)
    case unreachable(String)
    case timedOut(TimeInterval)
    case httpStatus(Int, String)
    case badAnswer(String)

    public var description: String {
        switch self {
        case .notLoopback(let host):
            "The model endpoint must be on this Mac (localhost, 127.0.0.1 or ::1); \(host) is not, so nothing was sent."
        case .invalidEndpoint(let detail): "The model endpoint is not usable: \(detail)."
        case .unreachable(let detail): "Could not reach the model endpoint: \(detail)."
        case .timedOut(let seconds): "The model did not answer within \(Int(seconds)) seconds."
        case .httpStatus(let status, let body): "The model endpoint answered HTTP \(status): \(body)"
        case .badAnswer(let detail): "The model's answer could not be read: \(detail)."
        }
    }
}
