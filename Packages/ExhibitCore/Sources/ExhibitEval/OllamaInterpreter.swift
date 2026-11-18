import ExhibitInterpret
import Foundation

/// A local model the person runs, reached over loopback HTTP (Ollama's `/api/chat`), with the answer constrained
/// by Ollama's structured output (`format` as a JSON Schema).
struct OllamaInterpreter: Interpreter {
    var model: String
    var endpoint = URL(string: "http://127.0.0.1:11434/api/chat")!
    /// Qwen-family models think before answering unless told not to; thinking costs seconds per instruction.
    var think = false

    var name: String { "ollama:\(model)" }

    func interpret(_ request: InterpretRequest) async throws -> InterpretOutcome {
        let listing = TargetListing(request)
        let body: [String: Any] = [
            "model": model,
            "stream": false,
            "think": think,
            "format": ModelPrompt.jsonSchema(refs: listing.refs),
            "options": ["temperature": 0, "seed": 1],
            "messages": [
                ["role": "system", "content": ModelPrompt.instructions],
                ["role": "user", "content": ModelPrompt.prompt(for: request, listing: listing)]
            ]
        ]
        let content = try await post(body)
        return .understood(try ModelPrompt.interpretation(fromJSON: content, listing: listing))
    }

    /// Loads the model so the first measured instruction does not pay for it.
    func warmUp() async throws {
        _ = try await post(["model": model, "stream": false, "think": think,
                            "messages": [["role": "user", "content": "Reply with {}"]], "format": "json"])
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
