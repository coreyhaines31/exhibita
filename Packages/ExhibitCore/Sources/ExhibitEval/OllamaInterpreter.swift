import ExhibitInterpret
import Foundation

/// A local model the person runs, reached over loopback HTTP (Ollama's `/api/chat`).
///
/// The answer is constrained by Ollama's structured output (`format` as a JSON Schema) when the model's runner
/// supports it. Some do not (Ollama answers "structured output is unavailable", as it did for the MLX-run model in
/// the spike); then the schema is described in the prompt instead, and refs are checked after the fact: unknown
/// refs are dropped, never guessed at.
struct OllamaInterpreter: Interpreter {
    var model: String
    var endpoint = URL(string: "http://127.0.0.1:11434/api/chat")!
    /// Qwen-family models think before answering unless told not to; thinking costs seconds per instruction.
    var think = false
    /// Set by `warmUp()`.
    var constrained = true

    var name: String { "ollama:\(model)" }

    static let unconstrainedSuffix = """

    Answer with one JSON object and nothing else, in exactly the form of the example: {"parts": [{"words": ..., \
    "mark": ..., "targets": [refs], "label": optional}]}.
    """

    func interpret(_ request: InterpretRequest) async throws -> InterpretOutcome {
        let listing = TargetListing(request)
        var body: [String: Any] = [
            "model": model,
            "stream": false,
            "think": think,
            "options": ["temperature": 0, "seed": 1, "num_predict": ModelPrompt.maxResponseTokens],
            "messages": [
                ["role": "system", "content": ModelPrompt.instructions + (constrained ? "" : Self.unconstrainedSuffix)],
                ["role": "user", "content": ModelPrompt.prompt(for: request, listing: listing)]
            ]
        ]
        if constrained { body["format"] = ModelPrompt.jsonSchema(refs: listing.refs) }
        let content = try await post(body)
        return .understood(try ModelPrompt.interpretation(fromJSON: Self.jsonObject(in: content), listing: listing))
    }

    /// Loads the model so the first measured instruction does not pay for it, and finds out whether the runner
    /// supports structured output.
    mutating func warmUp() async throws {
        let schema: [String: Any] = ["type": "object", "properties": ["ok": ["type": "boolean"]], "required": ["ok"]]
        do {
            _ = try await post(["model": model, "stream": false, "think": think, "format": schema,
                                "messages": [["role": "user", "content": "Reply {\"ok\": true}"]]])
        } catch let error as EvalError where error.description.contains("structured output is unavailable") {
            constrained = false
            log("ollama: structured output is unavailable for \(model); using an unconstrained JSON prompt")
            _ = try await post(["model": model, "stream": false, "think": think,
                                "messages": [["role": "user", "content": "Reply {\"ok\": true}"]]])
        }
    }

    /// The outermost `{...}` in a reply, so a stray code fence or sentence around the JSON does not fail it.
    static func jsonObject(in text: String) -> String {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end else { return text }
        return String(text[start...end])
    }

    private func post(_ body: [String: Any]) async throws -> String {
        guard endpoint.host == "127.0.0.1" || endpoint.host == "localhost" else {
            throw EvalError("the local model endpoint must be a loopback address")
        }
        var urlRequest = URLRequest(url: endpoint, timeoutInterval: 300)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = object["message"] as? [String: Any], let content = message["content"] as? String else {
            throw EvalError("Ollama answered: \(String(bytes: data.prefix(300), encoding: .utf8) ?? "?")")
        }
        return content
    }
}
