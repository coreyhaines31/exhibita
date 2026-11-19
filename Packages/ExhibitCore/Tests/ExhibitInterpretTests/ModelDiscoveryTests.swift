@testable import ExhibitInterpret
import Foundation
import Testing

/// Finding model servers on this Mac, with a fake fetch: no network.
struct ModelDiscoveryTests {
    struct Refused: Error {}

    /// Answers per URL; anything not listed is "nothing answering". Records every URL asked.
    final class FakeFetch: @unchecked Sendable {
        private let lock = NSLock()
        private var asked: [URL] = []
        let replies: [String: ModelHTTPResponse]

        init(_ replies: [String: ModelHTTPResponse]) {
            self.replies = replies
        }

        var urls: [URL] { lock.withLock { asked } }

        var fetch: ModelDiscovery.Fetch {
            { url, _ in
                self.lock.withLock { self.asked.append(url) }
                guard let reply = self.replies[url.absoluteString] else { throw Refused() }
                return reply
            }
        }
    }

    static let tags = "http://127.0.0.1:11434/api/tags"
    static let openAIModels = "http://127.0.0.1:1234/v1/models"

    static func json(_ text: String, status: Int = 200) -> ModelHTTPResponse {
        ModelHTTPResponse(status: status, body: Data(text.utf8))
    }

    @Test func findsOllamaAndAnOpenAICompatibleServer() async {
        let fake = FakeFetch([
            Self.tags: Self.json(#"{"models":[{"name":"ornith-1.5:9b"},{"name":"qwen3.8:27b"}]}"#),
            Self.openAIModels: Self.json(#"{"object":"list","data":[{"id":"qwen2.5-7b-instruct"}]}"#)
        ])
        let found = await ModelDiscovery.discover(fetch: fake.fetch)
        #expect(found.servers.map(\.kind) == [.ollama, .openAICompatible])
        #expect(found.servers[0].models == ["ornith-1.5:9b", "qwen3.8:27b"])
        #expect(found.servers[0].url.absoluteString == "http://127.0.0.1:11434")
        #expect(found.servers[1].models == ["qwen2.5-7b-instruct"])
        #expect(found.servers[1].url.absoluteString == "http://127.0.0.1:1234/v1")
        #expect(Set(fake.urls.map(\.absoluteString)) == [Self.tags, Self.openAIModels], "only the model lists")
    }

    @Test func eachFailureIsNamed() async {
        let fake = FakeFetch([Self.tags: Self.json(#"{"models":[]}"#),
                              Self.openAIModels: Self.json("<html>hello</html>")])
        let found = await ModelDiscovery.discover(fetch: fake.fetch)
        let empty = ModelServer(kind: .ollama, url: URL(string: "http://127.0.0.1:11434")!, models: [])
        #expect(found.probe(for: .ollama) == .noModels(empty))
        guard case .badAnswer(.openAICompatible, _, let detail) = found.probe(for: .openAICompatible) else {
            Issue.record("a page that is not a model list is a bad answer")
            return
        }
        #expect(detail == "not a model list")
        #expect(found.servers.isEmpty)
        #expect(found.defaultChoice == nil)

        let nothing = await ModelDiscovery.discover(fetch: FakeFetch([:]).fetch)
        #expect(nothing.probes.map(\.kind) == [.ollama, .openAICompatible])
        #expect(nothing.probes.allSatisfy { if case .notRunning = $0 { true } else { false } })

        let error = await ModelDiscovery.discover(fetch: FakeFetch([Self.tags: Self.json("{}", status: 500)]).fetch)
        #expect(error.probe(for: .ollama) == .badAnswer(.ollama, URL(string: "http://127.0.0.1:11434")!, "HTTP 500"))
    }

    @Test func onlyThisMacIsAsked() async {
        let fake = FakeFetch([:])
        let elsewhere = URL(string: "http://192.168.1.20:11434")!
        let named = URL(string: "http://my-mac.local:1234/v1")!
        let found = await ModelDiscovery.discover(candidates: [(.ollama, elsewhere), (.openAICompatible, named)],
                                                  fetch: fake.fetch)
        #expect(found.probes == [.notLoopback(.ollama, elsewhere), .notLoopback(.openAICompatible, named)])
        #expect(fake.urls.isEmpty, "nothing was sent")
        #expect(ModelDiscovery.candidates.allSatisfy { ModelEndpoint.isLoopback($0.url.host ?? "") })
    }

    @Test func theDefaultIsTheRecommendedModelThatIsInstalled() {
        let ollama = URL(string: "http://127.0.0.1:11434")!
        let lmStudio = URL(string: "http://127.0.0.1:1234/v1")!
        func server(_ kind: ModelServer.Kind, _ models: [String]) -> ModelServer {
            ModelServer(kind: kind, url: kind == .ollama ? ollama : lmStudio, models: models)
        }
        let both = [server(.ollama, ["llama3:8b", "ornith-1.5:9b", "qwen3.8:27b"])]
        #expect(RecommendedModels.pick(from: both)?.model == "qwen3.8:27b", "the eval's pick first")
        let fast = [server(.ollama, ["llama3:8b", "ornith-1.5:9b"])]
        #expect(RecommendedModels.pick(from: fast)?.model == "ornith-1.5:9b", "then the fast one")
        let other = [server(.ollama, ["llama3:8b", "mistral:7b"])]
        #expect(RecommendedModels.pick(from: other)?.model == "llama3:8b", "else the first listed")
        let onSecond = [server(.ollama, ["llama3:8b"]), server(.openAICompatible, ["qwen3.8:27b"])]
        let picked = RecommendedModels.pick(from: onSecond)
        #expect(picked?.model == "qwen3.8:27b" && picked?.server.kind == .openAICompatible)
        #expect(RecommendedModels.pick(from: []) == nil)
        #expect(RecommendedModels.pick(from: [server(.ollama, [])]) == nil)
    }
}

/// The real transport refuses any host that is not this Mac before it sends anything.
struct LoopbackTransportTests {
    @Test func getAndPostRefuseOtherHosts() {
        let transport = URLSessionModelTransport()
        #expect(throws: ModelError.notLoopback("example.com")) {
            try transport.get(URL(string: "http://example.com/api/tags")!, timeout: 1)
        }
        #expect(throws: ModelError.notLoopback("192.168.1.20")) {
            try transport.post(URL(string: "http://192.168.1.20:11434/api/chat")!, body: Data(), timeout: 1)
        }
    }
}

/// Which model is in effect and what Settings says about it, for each state of the setting and the discovery.
struct ModelChoiceTests {
    static let ollamaURL = URL(string: "http://127.0.0.1:11434")!
    static let lmStudioURL = URL(string: "http://127.0.0.1:1234/v1")!

    static func discovery(ollama: ServerProbe? = nil, lmStudio: ServerProbe? = nil) -> Discovery {
        Discovery(probes: [ollama ?? .notRunning(.ollama, ollamaURL),
                           lmStudio ?? .notRunning(.openAICompatible, lmStudioURL)])
    }

    static let installed = discovery(ollama: .found(ModelServer(kind: .ollama, url: ollamaURL,
                                                                models: ["ornith-1.5:9b", "qwen3.8:27b"])))

    @Test func neverChosenUsesTheRecommendedModelWithoutAClick() throws {
        let settings = ModelSettings()
        #expect(settings.effectiveChoice == nil)
        #expect(try settings.endpoint(discovery: nil) == nil, "nothing before discovery answers")
        #expect(settings.status(discovery: nil) == .checking)
        let endpoint = try #require(try settings.endpoint(discovery: Self.installed))
        #expect(endpoint.model == "qwen3.8:27b")
        #expect(endpoint.chatURL.absoluteString == "http://127.0.0.1:11434/api/chat")
        let status = settings.status(discovery: Self.installed)
        #expect(status == .using(model: "qwen3.8:27b", server: .ollama, isDefault: true))
        #expect(status.message == "Using qwen3.8:27b from Ollama on this Mac.")
        #expect(!status.isProblem)
    }

    @Test func choosingNoneIsNotTheSameAsNeverChoosing() throws {
        let none = ModelSettings(choice: ModelSettings.Choice.none)
        #expect(try none.endpoint(discovery: Self.installed) == nil, "None stays None with a model installed")
        #expect(none.status(discovery: Self.installed) == .builtInOnly)
        let data = try JSONEncoder().encode(none)
        #expect(try JSONDecoder().decode(ModelSettings.self, from: data).effectiveChoice == ModelSettings.Choice.none)
        let never = try JSONDecoder().decode(ModelSettings.self, from: JSONEncoder().encode(ModelSettings()))
        #expect(never.effectiveChoice == nil)
    }

    @Test func anExplicitChoiceIsNeverOverridden() throws {
        let fast = ModelSettings(choice: .installed(server: .ollama, url: Self.ollamaURL.absoluteString,
                                                    model: "ornith-1.5:9b"))
        #expect(try fast.endpoint(discovery: Self.installed)?.model == "ornith-1.5:9b")
        #expect(fast.status(discovery: Self.installed) == .using(model: "ornith-1.5:9b", server: .ollama, isDefault: false))
        // Gone or down: still that model, and the status says what is wrong.
        let gone = Self.discovery(ollama: .found(ModelServer(kind: .ollama, url: Self.ollamaURL, models: ["llama3:8b"])))
        #expect(try fast.endpoint(discovery: gone)?.model == "ornith-1.5:9b")
        let missing = fast.status(discovery: gone)
        #expect(missing == .chosenMissing(model: "ornith-1.5:9b", server: .ollama))
        #expect(missing.command == "ollama pull ornith-1.5:9b")
        let down = fast.status(discovery: Self.discovery())
        #expect(down == .serverDown(.ollama, model: "ornith-1.5:9b"))
        #expect(down.command == "ollama serve")
    }

    @Test func eachProblemSaysHowToFixIt() {
        let never = ModelSettings()
        let nothing = never.status(discovery: Self.discovery())
        #expect(nothing == .noServer)
        #expect(nothing.message.contains("ollama.com"))
        #expect(nothing.command == "ollama pull qwen3.8:27b")
        let empty = never.status(discovery: Self.discovery(ollama: .noModels(ModelServer(kind: .ollama,
                                                                                        url: Self.ollamaURL, models: []))))
        #expect(empty == .noModels(.ollama))
        #expect(empty.command == "ollama pull qwen3.8:27b")
        let odd = never.status(discovery: Self.discovery(ollama: .badAnswer(.ollama, Self.ollamaURL, "HTTP 500")))
        #expect(odd == .badAnswer(.ollama))
        #expect(odd.message.contains("127.0.0.1:11434"))
        let lmStudio = never.status(discovery: Self.discovery(lmStudio: .noModels(
            ModelServer(kind: .openAICompatible, url: Self.lmStudioURL, models: []))))
        #expect(lmStudio == .noModels(.openAICompatible))
        #expect(lmStudio.command == nil)
        for status in [nothing, empty, odd, lmStudio] { #expect(status.isProblem) }
    }

    @Test func otherUsesTheTypedFieldsAndStaysOnThisMac() throws {
        var other = ModelSettings(endpoint: "http://localhost:1234/v1", model: "", choice: .other)
        #expect(other.status(discovery: Self.installed) == .otherIncomplete)
        #expect(try other.endpoint(discovery: Self.installed) == nil)
        other.model = "my-model"
        #expect(try other.endpoint(discovery: Self.installed)?.api == .openai)
        #expect(other.status(discovery: nil) == .usingOther(model: "my-model", endpoint: "http://localhost:1234/v1"))
        other.endpoint = "http://192.168.1.20:11434"
        #expect(throws: ModelError.notLoopback("192.168.1.20")) { try other.endpoint(discovery: nil) }
        guard case .otherInvalid(let detail) = other.status(discovery: nil) else {
            Issue.record("a host that is not this Mac is a problem")
            return
        }
        #expect(detail.contains("192.168.1.20"))
    }

    @Test func aSettingFromBeforeTheChoiceKeepsItsModel() throws {
        let old = Data(#"{"enabled":true,"endpoint":"http://127.0.0.1:11434","model":"qwen3:8b","api":"automatic"}"#.utf8)
        let settings = try JSONDecoder().decode(ModelSettings.self, from: old)
        #expect(settings.effectiveChoice == .other)
        #expect(try settings.endpoint(discovery: Self.installed)?.model == "qwen3:8b")
        let off = Data(#"{"enabled":false,"endpoint":"http://127.0.0.1:11434","model":"","api":"automatic"}"#.utf8)
        #expect(try JSONDecoder().decode(ModelSettings.self, from: off).effectiveChoice == nil, "never chosen")
    }
}
