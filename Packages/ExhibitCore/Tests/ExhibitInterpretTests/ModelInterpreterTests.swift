import ExhibitCore
@testable import ExhibitInterpret
import Foundation
import Testing

/// A model endpoint that answers from a closure and records what it was sent. No real model runs.
final class FakeTransport: ModelTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var sent: [(url: URL, body: Data)] = []
    private let answer: @Sendable (URL, Data) throws -> ModelHTTPResponse

    init(answer: @escaping @Sendable (URL, Data) throws -> ModelHTTPResponse) {
        self.answer = answer
    }

    /// Replies like Ollama's `/api/chat` with `content` as the model's message.
    static func ollama(_ content: String) -> FakeTransport {
        FakeTransport { _, _ in
            let reply = try JSONSerialization.data(withJSONObject: ["message": ["role": "assistant", "content": content]])
            return ModelHTTPResponse(status: 200, body: reply)
        }
    }

    var requests: [(url: URL, body: Data)] { lock.withLock { sent } }

    func post(_ url: URL, body: Data, timeout: TimeInterval) throws -> ModelHTTPResponse {
        lock.withLock { sent.append((url, body)) }
        return try answer(url, body)
    }
}

struct ModelInterpreterTests {
    static func endpoint(_ url: String = "http://127.0.0.1:11434", api: ModelEndpoint.API? = nil) throws
        -> ModelEndpoint {
        try ModelEndpoint(url: try #require(URL(string: url)), model: "test-model", api: api)
    }

    @Test(arguments: ["http://127.0.0.1:11434", "http://localhost:1234/v1", "http://[::1]:8080", "http://127.0.0.2",
                      "https://LOCALHOST:443/api/chat"])
    func acceptsLoopbackHosts(_ url: String) throws {
        _ = try Self.endpoint(url)
    }

    @Test(arguments: ["http://192.168.1.10:11434", "http://example.com", "http://127.0.0.1.example.com",
                      "http://10.0.0.1", "http://0.0.0.0:11434", "http://[::2]:80", "http://localhost.example.com",
                      "http://128.0.0.1", "http://127.0.0.256"])
    func refusesEveryOtherHost(_ url: String) throws {
        #expect(throws: ModelError.self) { try Self.endpoint(url) }
        do {
            _ = try Self.endpoint(url)
        } catch let error as ModelError {
            guard case .notLoopback = error else { Issue.record("expected notLoopback, got \(error)"); return }
        }
    }

    @Test func refusesNonHTTPSchemes() {
        #expect(throws: ModelError.self) { try Self.endpoint("file:///tmp/model") }
        #expect(throws: ModelError.self) { try Self.endpoint("ftp://127.0.0.1/") }
    }

    @Test func theTransportItselfRefusesARemoteURL() throws {
        let url = try #require(URL(string: "http://example.com/api/chat"))
        #expect(throws: ModelError.notLoopback("example.com")) {
            try URLSessionModelTransport().post(url, body: Data(), timeout: 1)
        }
    }

    @Test func picksTheAPIFromThePath() throws {
        #expect(try Self.endpoint("http://127.0.0.1:11434").chatURL.absoluteString
                == "http://127.0.0.1:11434/api/chat")
        #expect(try Self.endpoint("http://127.0.0.1:1234/v1").chatURL.absoluteString
                == "http://127.0.0.1:1234/v1/chat/completions")
        #expect(try Self.endpoint("http://127.0.0.1:1234", api: .openai).chatURL.absoluteString
                == "http://127.0.0.1:1234/v1/chat/completions")
        #expect(try Self.endpoint("http://127.0.0.1:11434/api/chat").chatURL.absoluteString
                == "http://127.0.0.1:11434/api/chat")
    }

    @Test func keepsListedRefsAndDropsUnknownOnes() throws {
        let answer = #"""
        Sure! ```json
        {"parts":[{"words":"pricing","mark":"circle","targets":["t1","t99","T1"]},
                  {"words":"the logo","mark":"box","targets":["t42"]},
                  {"words":"emails","mark":"blur","targets":["t7"]},
                  {"words":"x","mark":"explode","targets":["t1"]}]}
        ```
        """#
        let interpreter = ModelInterpreter(endpoint: try Self.endpoint(), transport: FakeTransport.ollama(answer))
        let outcome = try interpreter.interpretNow(InterpretRequest(instruction: "circle pricing and box the logo",
                                                                    targets: Screen.targets))
        let listing = TargetListing(InterpretRequest(instruction: "", targets: Screen.targets))
        let seventh = try #require(listing.target(ref: "t7"))
        #expect(outcome == .understood(Interpretation(operations: [
            InterpretedOperation(mark: .circle, picks: [.id(Screen.pricing.id)]),
            InterpretedOperation(mark: .blur, picks: [.id(seventh.id)])
        ], notFound: ["the logo"])))
    }

    @Test func sendsTextOnlyWithSecretsMasked() throws {
        let secretLine = Target(kind: .text, text: "Key: \u{2022}\u{2022}\u{2022}\u{2022}",
                                rect: PixelRect(x: 0, y: 0, width: 80, height: 14))
        let key = Target(kind: .key, rect: PixelRect(x: 30, y: 0, width: 50, height: 14))
        let transport = FakeTransport.ollama(#"{"parts":[]}"#)
        let interpreter = ModelInterpreter(endpoint: try Self.endpoint(), transport: transport)
        _ = try interpreter.interpretNow(InterpretRequest(instruction: "hide the key", targets: [secretLine, key]))
        let sent = try #require(transport.requests.first)
        #expect(sent.url.absoluteString == "http://127.0.0.1:11434/api/chat")
        let body = try #require(try JSONSerialization.jsonObject(with: sent.body) as? [String: Any])
        #expect(Set(body.keys) == ["model", "stream", "think", "messages", "options"])
        #expect(body["format"] == nil)
        let text = try #require(String(bytes: sent.body, encoding: .utf8))
        #expect(text.contains("hide the key"))
        #expect(text.contains("hidden key or password"))
        #expect(!text.contains("image"))
    }

    @Test func readsOpenAICompatibleReplies() throws {
        let transport = FakeTransport { _, _ in
            let content = #"{"parts":[{"words":"sign up","mark":"arrow","targets":["t3"],"label":"here"}]}"#
            let reply: [String: Any] = ["choices": [["message": ["role": "assistant", "content": content]]]]
            return ModelHTTPResponse(status: 200, body: try JSONSerialization.data(withJSONObject: reply))
        }
        let interpreter = ModelInterpreter(endpoint: try Self.endpoint("http://localhost:1234/v1"),
                                           transport: transport)
        let outcome = try interpreter.interpretNow(InterpretRequest(instruction: "point at sign up and say here",
                                                                    targets: Screen.targets))
        #expect(outcome.interpretation?.operations
                == [InterpretedOperation(mark: .arrow, picks: [.id(Screen.signUp.id)], label: "here")])
        let sent = try #require(transport.requests.first)
        let body = try #require(try JSONSerialization.jsonObject(with: sent.body) as? [String: Any])
        #expect(body["response_format"] == nil)
        #expect(body["max_tokens"] as? Int == ModelPrompt.maxResponseTokens)
    }

    @Test func turnsReasoningOffOnBothAPIs() throws {
        let native = FakeTransport.ollama(#"{"parts":[]}"#)
        let request = InterpretRequest(instruction: "box the cheapest plan", targets: Screen.targets)
        _ = try ModelInterpreter(endpoint: try Self.endpoint(), transport: native).interpretNow(request)
        let nativeSent = try #require(native.requests.first)
        let nativeBody = try #require(try JSONSerialization.jsonObject(with: nativeSent.body) as? [String: Any])
        #expect(nativeBody["think"] as? Bool == false)

        let compatible = FakeTransport { _, _ in
            let reply: [String: Any] = ["choices": [["message": ["role": "assistant", "content": #"{"parts":[]}"#]]]]
            return ModelHTTPResponse(status: 200, body: try JSONSerialization.data(withJSONObject: reply))
        }
        _ = try ModelInterpreter(endpoint: try Self.endpoint("http://localhost:1234/v1"), transport: compatible)
            .interpretNow(request)
        let sent = try #require(compatible.requests.first)
        let body = try #require(try JSONSerialization.jsonObject(with: sent.body) as? [String: Any])
        #expect(body["reasoning_effort"] as? String == "none")
        #expect((body["chat_template_kwargs"] as? [String: Any])?["enable_thinking"] as? Bool == false)
    }

    @Test func asksAgainWithoutTheReasoningSwitchesWhenAServerRefusesThem() throws {
        let picky = FakeTransport { _, body in
            let sent = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            guard sent?["reasoning_effort"] == nil else {
                return ModelHTTPResponse(status: 400, body: Data("unknown field reasoning_effort".utf8))
            }
            let reply: [String: Any] = ["choices": [["message": ["role": "assistant", "content": #"{"parts":[]}"#]]]]
            return ModelHTTPResponse(status: 200, body: try JSONSerialization.data(withJSONObject: reply))
        }
        let outcome = try ModelInterpreter(endpoint: try Self.endpoint("http://localhost:1234/v1"), transport: picky)
            .interpretNow(InterpretRequest(instruction: "box the cheapest plan", targets: Screen.targets))
        #expect(outcome == .understood(Interpretation(operations: [])))
        #expect(picky.requests.count == 2)
    }

    @Test func reportsHTTPErrorsAndUnreadableAnswers() throws {
        let failing = FakeTransport { _, _ in ModelHTTPResponse(status: 404, body: Data("model not found".utf8)) }
        let request = InterpretRequest(instruction: "circle pricing", targets: Screen.targets)
        #expect(throws: ModelError.httpStatus(404, "model not found")) {
            try ModelInterpreter(endpoint: try Self.endpoint(), transport: failing).interpretNow(request)
        }
        #expect(throws: ModelError.self) {
            try ModelInterpreter(endpoint: try Self.endpoint(), transport: FakeTransport.ollama("no idea"))
                .interpretNow(request)
        }
    }

    @Test func readsTheServersTimings() throws {
        let ollama = FakeTransport { _, _ in
            let reply: [String: Any] = [
                "message": ["role": "assistant", "content": #"{"parts":[]}"#, "thinking": "hmm"],
                "total_duration": 3_000_000_000, "load_duration": 10_000_000, "prompt_eval_count": 1265,
                "prompt_eval_duration": 2_500_000_000, "eval_count": 29, "eval_duration": 400_000_000
            ]
            return ModelHTTPResponse(status: 200, body: try JSONSerialization.data(withJSONObject: reply))
        }
        let request = InterpretRequest(instruction: "box the cheapest plan", targets: Screen.targets)
        let native = try ModelInterpreter(endpoint: try Self.endpoint(), transport: ollama).interpretTimed(request)
        var expected = ModelTimings()
        expected.totalSeconds = 3
        expected.loadSeconds = 0.01
        expected.promptTokens = 1265
        expected.promptSeconds = 2.5
        expected.outputTokens = 29
        expected.outputSeconds = 0.4
        expected.thinkingCharacters = 3
        #expect(native.timings == expected)

        let openAI = FakeTransport { _, _ in
            let reply: [String: Any] = [
                "choices": [["message": ["role": "assistant", "content": #"{"parts":[]}"#]]],
                "usage": ["prompt_tokens": 757, "prompt_tokens_details": ["cached_tokens": 467], "completion_tokens": 45]
            ]
            return ModelHTTPResponse(status: 200, body: try JSONSerialization.data(withJSONObject: reply))
        }
        let compatible = try ModelInterpreter(endpoint: try Self.endpoint("http://localhost:1234/v1"),
                                              transport: openAI).interpretTimed(request)
        #expect(compatible.timings?.promptTokens == 757)
        #expect(compatible.timings?.cachedPromptTokens == 467)
        #expect(compatible.timings?.outputTokens == 45)
        #expect(compatible.timings?.promptSeconds == nil)
        #expect(try ModelInterpreter(endpoint: try Self.endpoint(), transport: FakeTransport.ollama(#"{"parts":[]}"#))
            .interpretTimed(request).timings == nil)
    }

    @Test func timesOutAgainstASilentLoopbackServer() throws {
        let server = try SilentServer()
        defer { server.stop() }
        let url = try #require(URL(string: "http://127.0.0.1:\(server.port)/api/chat"))
        let start = Date()
        #expect(throws: ModelError.timedOut(1)) {
            try URLSessionModelTransport().post(url, body: Data("{}".utf8), timeout: 1)
        }
        #expect(Date().timeIntervalSince(start) < 5)
    }

    @Test func chainsAfterTheGrammar() async throws {
        let transport = FakeTransport.ollama(#"{"parts":[{"words":"x","mark":"highlight","targets":["t1"]}]}"#)
        let chain = ChainedInterpreter([GrammarInterpreter(),
                                        ModelInterpreter(endpoint: try Self.endpoint(), transport: transport)])
        let grammarOnly = try await chain.interpret(InterpretRequest(instruction: "blur the keys",
                                                                     targets: Screen.targets))
        #expect(grammarOnly.interpretation?.operations.first?.picks == [.kind(.key)])
        #expect(transport.requests.isEmpty)
        let modelAnswered = try await chain.interpret(InterpretRequest(instruction: "highlight anything important",
                                                                       targets: Screen.targets))
        #expect(modelAnswered.interpretation?.operations.first?.mark == .highlight)
        #expect(transport.requests.count == 1)
    }
}

/// A loopback TCP server that accepts connections and never answers, for the timeout test.
final class SilentServer: @unchecked Sendable {
    let port: UInt16
    private let socket: Int32
    private var accepted: [Int32] = []
    private let lock = NSLock()

    init() throws {
        let listening = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        address.sin_port = 0
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(listening, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0, listen(listening, 4) == 0 else { throw ModelError.unreachable("could not listen") }
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(listening, $0, &length) }
        }
        socket = listening
        port = UInt16(bigEndian: address.sin_port)
        Thread.detachNewThread { [weak self] in
            while true {
                let client = accept(listening, nil, nil)
                guard client >= 0 else { return }
                self?.keep(client)
            }
        }
    }

    private func keep(_ client: Int32) {
        lock.withLock { accepted.append(client) }
    }

    func stop() {
        close(socket)
        lock.withLock { accepted.forEach { close($0) } }
    }
}
