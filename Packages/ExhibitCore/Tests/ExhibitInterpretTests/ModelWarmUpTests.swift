import ExhibitCore
@testable import ExhibitInterpret
import Foundation
import Testing

/// The warm-up: what it sends (exactly the start of the instruction's request, nothing more) and when it is sent
/// (once per screen and model, again after another screen or once the server has likely unloaded the model).
@Suite(.timeLimit(.minutes(1))) struct ModelWarmUpTests {
    static func interpreter(_ transport: FakeTransport, _ warmUps: ModelWarmUps = ModelWarmUps(),
                            url: String = "http://127.0.0.1:11434", use: ModelUse = ModelUse()) throws
        -> ModelInterpreter {
        ModelInterpreter(endpoint: try ModelInterpreterTests.endpoint(url), transport: transport, warmUps: warmUps,
                         use: use)
    }

    static func messages(_ body: Data) throws -> [[String: String]] {
        let object = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        return try #require(object["messages"] as? [[String: String]])
    }

    @Test func theWarmUpIsTheStartOfTheInstructionsRequestWithAOneTokenAnswer() throws {
        let transport = FakeTransport.ollama(#"{"parts":[]}"#)
        let model = try Self.interpreter(transport)
        #expect(try model.warmUpNow(Screen.targets) != nil)
        let request = InterpretRequest(instruction: "box the cheapest plan", targets: Screen.targets,
                                       pointer: PixelPoint(x: 205, y: 25))
        _ = try model.interpretNow(request)
        let sent = transport.requests
        #expect(sent.count == 2)
        #expect(sent.allSatisfy { $0.url.absoluteString == "http://127.0.0.1:11434/api/chat" })
        let warm = try Self.messages(sent[0].body)
        let real = try Self.messages(sent[1].body)
        #expect(warm.map { $0["role"] } == ["system", "user"])
        #expect(Array(real.prefix(warm.count)) == warm, "the instruction's request begins with the warm-up")
        #expect(real.map { $0["role"] } == ["system", "user", "assistant", "user"])
        #expect(real.last?["content"]?.contains("Instruction: box the cheapest plan") == true)
        #expect(real.last?["content"]?.contains("The pointer is at") == true, "the pointer goes with the instruction")
        let screen = try #require(warm.last?["content"])
        #expect(screen.hasPrefix("Screen:\n"))
        #expect(!screen.contains("Instruction:"), "the warm-up knows nothing of the instruction")
        #expect(!screen.contains("pointer"))
        let warmBody = try JSONSerialization.jsonObject(with: sent[0].body) as? [String: Any]
        let options = try #require(warmBody?["options"] as? [String: Any])
        #expect(options["num_predict"] as? Int == 1)
    }

    @Test func theWarmUpMasksSecretsAsTheRequestDoes() throws {
        let secretLine = Target(kind: .text, text: "Key: \u{2022}\u{2022}\u{2022}\u{2022}",
                                rect: PixelRect(x: 0, y: 0, width: 80, height: 14))
        let key = Target(kind: .key, rect: PixelRect(x: 30, y: 0, width: 50, height: 14))
        let transport = FakeTransport.ollama("{")
        try Self.interpreter(transport).warmUpNow([secretLine, key])
        let sent = try #require(transport.requests.first)
        let text = try #require(String(bytes: sent.body, encoding: .utf8))
        #expect(text.contains("hidden key or password"))
    }

    @Test func openAICompatibleWarmUpsCapTheAnswerAtOneToken() throws {
        let transport = FakeTransport { _, _ in
            let reply: [String: Any] = ["choices": [["message": ["role": "assistant", "content": "{"]]]]
            return ModelHTTPResponse(status: 200, body: try JSONSerialization.data(withJSONObject: reply))
        }
        try Self.interpreter(transport, url: "http://localhost:1234/v1").warmUpNow(Screen.targets)
        let sent = try #require(transport.requests.first)
        #expect(sent.url.absoluteString == "http://localhost:1234/v1/chat/completions")
        let body = try #require(try JSONSerialization.jsonObject(with: sent.body) as? [String: Any])
        #expect(body["max_tokens"] as? Int == 1)
    }

    @Test func aScreenIsWarmedOnceUntilAnotherIsWarmed() throws {
        let transport = FakeTransport.ollama("{")
        let model = try Self.interpreter(transport)
        let other = [Screen.reply, Screen.forward]
        #expect(try model.warmUpNow(Screen.targets) != nil)
        #expect(try model.warmUpNow(Screen.targets) == nil)
        #expect(try model.warmUpNow(other) != nil)
        #expect(try model.warmUpNow(Screen.targets) != nil, "the other screen took the server's cache")
        #expect(transport.requests.count == 3)
    }

    @Test func anotherModelOrServerIsWarmedOnItsOwn() throws {
        let transport = FakeTransport.ollama("{")
        let warmUps = ModelWarmUps()
        try Self.interpreter(transport, warmUps).warmUpNow(Screen.targets)
        try Self.interpreter(transport, warmUps, url: "http://127.0.0.1:8080").warmUpNow(Screen.targets)
        #expect(transport.requests.count == 2)
    }

    @Test func aScreenIsWarmedAgainOnceTheModelHasLikelyUnloaded() throws {
        let clock = TestClock()
        let transport = FakeTransport.ollama("{")
        let model = try Self.interpreter(transport, ModelWarmUps(staleAfter: .seconds(240), now: clock.now))
        try model.warmUpNow(Screen.targets)
        clock.advance(.seconds(200))
        try model.warmUpNow(Screen.targets)
        #expect(transport.requests.count == 1)
        clock.advance(.seconds(41))
        try model.warmUpNow(Screen.targets)
        #expect(transport.requests.count == 2)
    }

    @Test func aFailedWarmUpIsTriedAgainNextTime() throws {
        let failing = FakeTransport { _, _ in throw ModelError.unreachable("connection refused") }
        let warmUps = ModelWarmUps()
        #expect(throws: ModelError.self) { try Self.interpreter(failing, warmUps).warmUpNow(Screen.targets) }
        let working = FakeTransport.ollama("{")
        #expect(try Self.interpreter(working, warmUps).warmUpNow(Screen.targets) != nil)
    }

    @Test func aScreenWithNothingToReadSendsNothing() throws {
        let transport = FakeTransport.ollama("{")
        #expect(try Self.interpreter(transport).warmUpNow([]) == nil)
        #expect(transport.requests.isEmpty)
    }

    @Test func theBackgroundWarmUpReturnsAtOnce() async throws {
        let gate = DispatchSemaphore(value: 0)
        let transport = FakeTransport { _, _ in
            gate.wait()
            return ModelHTTPResponse(status: 200, body: Data(#"{"message":{"content":"{"}}"#.utf8))
        }
        try Self.interpreter(transport).warmUp(Screen.targets)
        gate.signal()
        for _ in 0..<500 where transport.requests.isEmpty {
            try await Task.sleep(for: .milliseconds(2))
        }
        #expect(transport.requests.count == 1)
    }
}

/// Which models the server holds in memory: Ollama's `/api/ps`, asked only of a loopback server.
@Suite(.timeLimit(.minutes(1))) struct ModelLoadedTests {
    /// Answers `GET /api/ps` with these model names, and chats like Ollama.
    static func server(loaded: [String]?) -> FakeTransport {
        FakeTransport(answer: { _, _ in
            ModelHTTPResponse(status: 200, body: Data(#"{"message":{"content":"{"}}"#.utf8))
        }, get: { url, _ in
            guard url.absoluteString == "http://127.0.0.1:11434/api/ps", let loaded else {
                throw ModelError.unreachable(url.absoluteString)
            }
            let models = loaded.map { ["name": $0, "model": $0] }
            return ModelHTTPResponse(status: 200, body: try JSONSerialization.data(withJSONObject: ["models": models]))
        })
    }

    @Test func aLoadedModelIsSeenAsLoaded() throws {
        let model = try ModelWarmUpTests.interpreter(Self.server(loaded: ["ornith-1.5:9b", "test-model"]))
        #expect(model.isLoaded())
    }

    @Test func anotherLoadedModelOrNoneIsNotLoaded() throws {
        #expect(!(try ModelWarmUpTests.interpreter(Self.server(loaded: ["qwen3.8:27b"])).isLoaded()))
        #expect(!(try ModelWarmUpTests.interpreter(Self.server(loaded: [])).isLoaded()))
        #expect(!(try ModelWarmUpTests.interpreter(Self.server(loaded: nil)).isLoaded()), "a failed ask is no")
    }

    @Test func anUntaggedNameMatchesLatest() throws {
        let transport = Self.server(loaded: ["test-model:latest"])
        let model = ModelInterpreter(endpoint: try ModelEndpoint(url: ModelEndpoint.defaultURL, model: "test-model"),
                                     transport: transport, warmUps: ModelWarmUps())
        #expect(model.isLoaded())
    }

    /// A `ModelUse` that saw the model asked just now, on a clock the test moves.
    static func recentUse(_ clock: TestClock = TestClock()) -> ModelUse {
        let use = ModelUse(now: clock.now)
        use.record()
        return use
    }

    /// Waits for the background warm-up to ask and, maybe, to send.
    static func settle(_ transport: FakeTransport) async throws {
        for _ in 0..<100 where transport.gets.isEmpty {
            try await Task.sleep(for: .milliseconds(2))
        }
        try await Task.sleep(for: .milliseconds(50))
    }

    @Test func anOpenAICompatibleServerIsNeverAskedAndNeverWarmedAtOpen() async throws {
        let transport = Self.server(loaded: ["test-model"])
        let model = try ModelWarmUpTests.interpreter(transport, url: "http://localhost:1234/v1", use: Self.recentUse())
        #expect(!model.isLoaded())
        model.warmUpIfLoaded(Screen.targets)
        try await Task.sleep(for: .milliseconds(100))
        #expect(transport.requests.isEmpty)
        #expect(transport.gets.isEmpty)
    }

    @Test func noRecentUseMeansTheServerIsNotEvenAsked() async throws {
        let loaded = Self.server(loaded: ["test-model"])
        try ModelWarmUpTests.interpreter(loaded, use: ModelUse()).warmUpIfLoaded(Screen.targets)
        try await Task.sleep(for: .milliseconds(100))
        #expect(loaded.gets.isEmpty, "no /api/ps without recent use")
        #expect(loaded.requests.isEmpty)
    }

    @Test func recentUseAndLoadedWarmsUp() async throws {
        let loaded = Self.server(loaded: ["test-model"])
        try ModelWarmUpTests.interpreter(loaded, use: Self.recentUse()).warmUpIfLoaded(Screen.targets)
        for _ in 0..<500 where loaded.requests.isEmpty {
            try await Task.sleep(for: .milliseconds(2))
        }
        #expect(loaded.gets.count == 1)
        #expect(loaded.requests.count == 1)
    }

    @Test func recentUseButNotLoadedSendsNothing() async throws {
        let unloaded = Self.server(loaded: [])
        try ModelWarmUpTests.interpreter(unloaded, use: Self.recentUse()).warmUpIfLoaded(Screen.targets)
        try await Self.settle(unloaded)
        #expect(unloaded.gets.count == 1)
        #expect(unloaded.requests.isEmpty, "nothing loaded, nothing sent")
    }

    @Test func useOlderThanTenMinutesDoesNotCount() async throws {
        let clock = TestClock()
        let use = Self.recentUse(clock)
        clock.advance(.seconds(600))
        #expect(use.isRecent(), "ten minutes is still recent")
        clock.advance(.seconds(1))
        #expect(!use.isRecent())
        let loaded = Self.server(loaded: ["test-model"])
        try ModelWarmUpTests.interpreter(loaded, use: use).warmUpIfLoaded(Screen.targets)
        try await Task.sleep(for: .milliseconds(100))
        #expect(loaded.gets.isEmpty)
        #expect(loaded.requests.isEmpty)
    }

    @Test func askingTheModelAnInstructionCountsAsUse() throws {
        let use = ModelUse()
        let failing = FakeTransport { _, _ in throw ModelError.unreachable("connection refused") }
        let model = try ModelWarmUpTests.interpreter(failing, use: use)
        #expect(!use.isRecent())
        _ = try? model.interpretNow(InterpretRequest(instruction: "box the cheapest plan", targets: Screen.targets))
        #expect(use.isRecent(), "tried counts, answered or not")
    }

    @Test func aWarmUpIsNotUse() throws {
        let use = ModelUse()
        try ModelWarmUpTests.interpreter(FakeTransport.ollama("{"), use: use).warmUpNow(Screen.targets)
        #expect(!use.isRecent())
    }
}

/// A clock the test moves by hand.
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = ContinuousClock.now

    var now: @Sendable () -> ContinuousClock.Instant {
        { [self] in lock.withLock { current } }
    }

    func advance(_ duration: Duration) {
        lock.withLock { current += duration }
    }
}
