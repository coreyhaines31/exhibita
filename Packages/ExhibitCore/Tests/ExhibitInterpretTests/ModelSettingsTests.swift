import ExhibitCore
@testable import ExhibitInterpret
import Foundation
import Testing

/// The app's free-form setting and its Test button, with a fake transport: no network.
struct ModelSettingsTests {
    @Test func offByDefaultAndOffMeansNoModel() throws {
        let settings = ModelSettings()
        #expect(!settings.enabled)
        #expect(settings.endpoint == "http://127.0.0.1:11434")
        #expect(try settings.modelEndpoint() == nil)
        var named = settings
        named.model = "qwen3:8b"
        #expect(try named.modelEndpoint() == nil, "off, even with a model named")
        named.enabled = true
        #expect(try named.modelEndpoint()?.model == "qwen3:8b")
        named.model = "  "
        #expect(try named.modelEndpoint() == nil, "on with no model name is no model")
    }

    @Test func onlyThisMacIsAccepted() {
        let remote = ModelSettings(enabled: true, endpoint: "http://192.168.1.20:11434", model: "m")
        #expect(throws: ModelError.notLoopback("192.168.1.20")) { try remote.modelEndpoint() }
        let named = ModelSettings(enabled: true, endpoint: "http://my-mac.local:11434", model: "m")
        #expect(throws: ModelError.notLoopback("my-mac.local")) { try named.modelEndpoint() }
        let local = ModelSettings(enabled: true, endpoint: "http://localhost:1234/v1", model: "m")
        #expect((try? local.modelEndpoint())??.api == .openai)
    }

    @Test func aReachableModelReportsItsTime() {
        var ticks = [Date(timeIntervalSince1970: 0), Date(timeIntervalSince1970: 2.5)]
        let transport = FakeTransport.ollama("OK")
        let result = ModelProbe.run(ModelSettings(model: "qwen3.8:27b"), transport: transport,
                                    now: { ticks.removeFirst() })
        #expect(result == .reachable(model: "qwen3.8:27b", seconds: 2.5))
        #expect(result.message.hasPrefix("Reachable. qwen3.8:27b answered in 2.5 s"))
        #expect(transport.requests.first?.url.absoluteString == "http://127.0.0.1:11434/api/chat")
        let body = String(bytes: transport.requests.first?.body ?? Data(), encoding: .utf8) ?? ""
        #expect(body.contains("\"think\":false"))
    }

    @Test func aMissingModelIsNamed() {
        let transport = FakeTransport { _, _ in
            ModelHTTPResponse(status: 404, body: Data(#"{"error":"model 'qwen3:8b' not found"}"#.utf8))
        }
        let result = ModelProbe.run(ModelSettings(model: "qwen3:8b"), transport: transport)
        #expect(result == .modelMissing("qwen3:8b"))
        #expect(result.message.contains("ollama pull qwen3:8b"))
    }

    @Test func nothingIsSentToAnotherMachine() {
        let transport = FakeTransport.ollama("OK")
        let result = ModelProbe.run(ModelSettings(endpoint: "http://example.com:11434", model: "m"),
                                    transport: transport)
        #expect(result == .notLoopback("example.com"))
        #expect(transport.requests.isEmpty)
    }

    @Test func aStoppedServerIsUnreachable() {
        let transport = FakeTransport { _, _ in throw ModelError.unreachable("connection refused") }
        let result = ModelProbe.run(ModelSettings(model: "m"), transport: transport)
        #expect(result == .unreachable("http://127.0.0.1:11434"))
        #expect(result.message == "Nothing is answering at http://127.0.0.1:11434. Is the model server running?")
    }

    @Test func settingsRoundTrip() throws {
        let settings = ModelSettings(enabled: true, endpoint: "http://127.0.0.1:1234/v1", model: "m", api: .openai)
        let data = try JSONEncoder().encode(settings)
        #expect(try JSONDecoder().decode(ModelSettings.self, from: data) == settings)
    }
}
