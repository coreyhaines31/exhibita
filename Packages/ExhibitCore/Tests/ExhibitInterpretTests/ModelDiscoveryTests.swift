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
