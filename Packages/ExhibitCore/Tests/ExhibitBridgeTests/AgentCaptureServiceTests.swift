import CoreGraphics
@testable import ExhibitBridge
import ExhibitCore
import ExhibitFixtures
import ExhibitShell
import ExhibitStore
import Foundation
import Testing

/// Hands back a fixture image, or the error it was given. No ScreenCaptureKit.
struct FakeProvider: CaptureProvider {
    var result: Result<ProvidedCapture, BridgeError>
    var seen: Recorder<CaptureTarget>?

    func capture(_ target: CaptureTarget, policy: CapturePolicy) async throws -> ProvidedCapture {
        seen?.append(target)
        return try result.get()
    }
}

final class Recorder<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [Value] = []
    func append(_ value: Value) { lock.withLock { stored.append(value) } }
    var values: [Value] { lock.withLock { stored } }
}

@Suite(.serialized, .timeLimit(.minutes(1))) struct AgentCaptureServiceTests {
    let fixture = sampleFixture()
    let email = Target(kind: .email, rect: PixelRect(x: 400, y: 300, width: 300, height: 30))
    let key = Target(kind: .key, rect: PixelRect(x: 400, y: 400, width: 300, height: 30))
    let line = Target(kind: .text, text: "Billing", rect: PixelRect(x: 40, y: 100, width: 120, height: 30))

    func store() throws -> CaptureStore {
        CaptureStore(directory: ExhibitPaths.capturesDirectory(in: try shortTemporaryDirectory()))
    }

    func service(_ store: CaptureStore, policy: CapturePolicy = CapturePolicy(),
                 provider: FakeProvider? = nil, captured: Recorder<UUID> = Recorder(),
                 shown: Recorder<UUID> = Recorder(), targetsFail: Bool = false) -> AgentCaptureService {
        let targets = [line, email, key]
        let image = fixture.image
        return AgentCaptureService(
            store: store,
            provider: provider ?? FakeProvider(result: .success(ProvidedCapture(image: image, scale: 2,
                                                                                 appName: "Safari",
                                                                                 windowTitle: "Billing"))),
            policy: { policy },
            findTargets: { _ in
                if targetsFail { throw ExhibitError.renderFailed }
                return targets
            },
            present: { id in
                shown.append(id)
                return true
            },
            didCapture: { captured.append($0) })
    }

    @Test func captureSavesAnAgentCaptureAndBlursSecretsInTheAgentsCopy() async throws {
        let store = try store()
        let captured = Recorder<UUID>()
        let response = await service(store, captured: captured).handle(
            BridgeRequest(id: "c", method: .capture, capture: CaptureParameters(window: "Safari")))
        let result = try #require(response.capture)
        #expect(response.id == "c")
        #expect(response.error == nil)
        #expect(captured.values == [result.id])
        #expect(result.autoBlur == .init(enabled: true, blurred: 2, kinds: ["email": 1, "key": 1]))
        #expect(result.targets == 3)
        #expect(result.appName == "Safari")
        #expect(result.width == fixture.image.width)
        #expect(result.bundle == nil, "the unblurred original is not one path away from the blurred copy")
        #expect(result.image == store.exportURL(for: result.id).path)

        let item = try #require(store.list().first)
        #expect(item.byAgent)
        #expect(item.id == result.id)
        let loaded = try store.load(result.id)
        #expect(loaded.document.source?.capturedBy == .agent)
        #expect(loaded.document.targets.count == 3)
        #expect(loaded.document.marks.map(\.kind) == [.blur, .blur])
        #expect(Set(loaded.document.marks.compactMap(\.targetID)) == [email.id, key.id])
        // The original is untouched; the agent's copy is the renderer's output with the blurs.
        #expect(try PNG.encode(loaded.original) == PNG.encode(fixture.image))
        let agentCopy = try Data(contentsOf: URL(fileURLWithPath: result.image))
        #expect(agentCopy == (try PNG.encode(Renderer.render(loaded.document, original: loaded.original))))
        #expect(agentCopy != (try PNG.encode(fixture.image)))
    }

    @Test func autoBlurOffLeavesTheCopyUnmarked() async throws {
        let store = try store()
        let response = await service(store, policy: CapturePolicy(agentAutoBlur: false))
            .handle(BridgeRequest(method: .capture))
        let result = try #require(response.capture)
        #expect(result.autoBlur == .init(enabled: false, blurred: 0, kinds: [:]))
        #expect(try store.load(result.id).document.marks.isEmpty)
        #expect(try Data(contentsOf: URL(fileURLWithPath: result.image)) == PNG.encode(fixture.image))
        #expect(result.bundle == store.url(for: result.id).path, "nothing was redacted, so nothing to withhold")
    }

    @Test func theBundleIsGivenWhenAutoBlurFindsNothing() async throws {
        let store = try store()
        let response = await service(store, policy: CapturePolicy(autoBlurKinds: [.phone]))
            .handle(BridgeRequest(method: .capture))
        let result = try #require(response.capture)
        #expect(result.autoBlur.blurred == 0)
        #expect(result.bundle == store.url(for: result.id).path)
    }

    @Test func failedTextReadingGivesTheAgentNothing() async throws {
        let store = try store()
        let captured = Recorder<UUID>()
        let response = await service(store, captured: captured, targetsFail: true)
            .handle(BridgeRequest(method: .capture))
        #expect(response.capture == nil)
        #expect(response.error?.code == "capture_failed")
        let item = try #require(store.list().first)
        #expect(captured.values == [item.id])
        #expect(!FileManager.default.fileExists(atPath: store.exportURL(for: item.id).path))
    }

    @Test func providerErrorsPassThroughAndSaveNothing() async throws {
        let store = try store()
        for code in [BridgeError.Code.permissionNotGranted, .windowNotFound, .neverCapture, .displayNotFound] {
            let provider = FakeProvider(result: .failure(BridgeError(code, "no")))
            let response = await service(store, provider: provider).handle(BridgeRequest(method: .capture))
            #expect(response.error?.code == code.rawValue)
        }
        #expect(store.list().isEmpty)
    }

    @Test func badParametersNeverReachTheProvider() async throws {
        let seen = Recorder<CaptureTarget>()
        let provider = FakeProvider(result: .success(ProvidedCapture(image: fixture.image, scale: 2)), seen: seen)
        let response = await service(try store(), provider: provider).handle(
            BridgeRequest(method: .capture, capture: CaptureParameters(window: "Safari", display: 2)))
        #expect(response.error?.code == "bad_request")
        #expect(seen.values.isEmpty)
    }

    @Test func openShowsAKnownCaptureOnly() async throws {
        let store = try store()
        let shown = Recorder<UUID>()
        let service = service(store, shown: shown)
        let unknown = await service.handle(BridgeRequest(method: .open, open: OpenParameters(captureID: UUID())))
        #expect(unknown.error?.code == "unknown_capture")
        let id = try #require(await service.handle(BridgeRequest(method: .capture)).capture?.id)
        let opened = await service.handle(BridgeRequest(method: .open, open: OpenParameters(captureID: id)))
        #expect(opened.open == OpenResult(id: id, shown: true))
        #expect(shown.values == [id])
        #expect(await service.handle(BridgeRequest(method: .open)).error?.code == "bad_request")
    }

    @Test func pingAndUnknownMethods() async throws {
        let service = service(try store())
        #expect(await service.handle(BridgeRequest(id: "p", method: .ping)) == BridgeResponse(id: "p", pong: true))
        var request = BridgeRequest(method: .ping)
        request.method = "zap"
        #expect(await service.handle(request).error?.code == "unknown_method")
    }

    /// The whole path in process: client, socket, server, service, fake provider, store.
    @Test func endToEndOverTheSocket() async throws {
        let support = try shortTemporaryDirectory()
        let store = CaptureStore(directory: ExhibitPaths.capturesDirectory(in: support))
        let service = service(store)
        let url = BridgeSocket.url(inSupportDirectory: support)
        let server = BridgeServer(socketURL: url) { await service.handle($0) }
        try server.start()
        defer { server.stop() }
        let response = try await Task.detached {
            try BridgeClient(socketURL: url, timeout: 10).send(BridgeRequest(method: .capture))
        }.value
        let result = try #require(response.capture)
        #expect(FileManager.default.fileExists(atPath: result.image))
        #expect(store.list().map(\.id) == [result.id])
    }
}
