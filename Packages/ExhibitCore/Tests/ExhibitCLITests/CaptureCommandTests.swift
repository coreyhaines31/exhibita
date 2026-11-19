import CoreGraphics
import ExhibitBridge
@testable import ExhibitCLI
import ExhibitCore
import ExhibitFixtures
import ExhibitShell
import ExhibitStore
import Foundation
import Testing

/// A support directory short enough for a Unix socket path, under /tmp. `EXHIBIT_SUPPORT_DIR` points the CLI at
/// it, so these tests never touch the real app's socket or history.
func shortSupportDirectory() throws -> URL {
    let url = URL(fileURLWithPath: "/tmp", isDirectory: true)
        .appendingPathComponent("exc-\(UUID().uuidString.prefix(8))", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private struct FixtureProvider: CaptureProvider {
    func capture(_ target: CaptureTarget, policy: CapturePolicy) async throws -> ProvidedCapture {
        if case .window(let name) = target, name == "Keychain Access" {
            throw BridgeError(.neverCapture, "Keychain Access is on the never-capture list")
        }
        return ProvidedCapture(image: sampleFixture().image, scale: 2, appName: "Safari", windowTitle: "Billing")
    }
}

@Suite(.serialized, .timeLimit(.minutes(2))) struct CaptureCommandTests {
    let support: URL
    var environment: [String: String] { [ExhibitPaths.supportOverrideVariable: support.path] }
    var store: CaptureStore { CaptureStore(directory: ExhibitPaths.capturesDirectory(in: support)) }

    init() throws {
        support = try shortSupportDirectory()
    }

    func run(_ arguments: [String]) -> CLIResult {
        CLI.run(arguments: arguments, environment: environment)
    }

    /// Serves the bridge from `support` with `handler` while `body` runs.
    func serving<T>(_ handler: @escaping BridgeServer.Handler, _ body: () throws -> T) throws -> T {
        let server = BridgeServer(socketURL: BridgeSocket.url(inSupportDirectory: support), handler: handler)
        try server.start()
        defer { server.stop() }
        return try body()
    }

    func service() -> AgentCaptureService {
        let email = Target(kind: .email, rect: PixelRect(x: 400, y: 300, width: 300, height: 30))
        let line = Target(kind: .text, text: "Billing", rect: PixelRect(x: 40, y: 100, width: 120, height: 30))
        return AgentCaptureService(store: store, provider: FixtureProvider(), policy: { CapturePolicy() },
                                   findTargets: { _ in [line, email] }, present: { _ in true })
    }

    // MARK: No app running

    @Test func captureWithoutTheAppSaysSoAndStartsNothing() throws {
        let result = run(["capture", "--window", "Safari"])
        #expect(result.status == .appNotRunning)
        #expect(result.status.rawValue == 7)
        #expect(result.stdout.isEmpty)
        let error = try errorBody(result)
        #expect(error["code"] as? String == "app_not_running")
        #expect(error["exitCode"] as? Int == 7)
        #expect((error["message"] as? String)?.contains("open Exhibit A") == true)
        // Nothing was created: no socket, no history.
        #expect(!FileManager.default.fileExists(atPath: BridgeSocket.url(inSupportDirectory: support).path))
        #expect(store.list().isEmpty)
    }

    @Test func openWithoutTheAppSaysSo() throws {
        let result = run(["open", UUID().uuidString])
        #expect(result.status == .appNotRunning)
        #expect(try errorBody(result)["code"] as? String == "app_not_running")
    }

    @Test func badArgumentsAreUsageErrorsBeforeAnyConnection() throws {
        for arguments in [["capture", "--window", "Safari", "--region", "0,0,10,10"],
                          ["capture", "--window", "Safari", "--screen"],
                          ["capture", "--screen", "--display", "2"],
                          ["capture", "--region", "0,0,0,10"],
                          ["capture", "--timeout", "0"],
                          ["open", "not-an-id"]] {
            let result = run(arguments)
            #expect(result.status == .usage, "\(arguments)")
            #expect(try errorBody(result)["code"] as? String == "usage", "\(arguments)")
        }
    }

    // MARK: With a bridge

    @Test func captureReturnsTheAgentCopyAndTheIdWorksAsAnInput() throws {
        let service = service()
        let capture = try serving({ await service.handle($0) }, { run(["capture", "--window", "Safari"]) })
        #expect(capture.status == .success, "\(capture.stderr)")
        let output = try json(capture.stdout)
        let id = try #require(output["id"] as? String)
        #expect(output["capturedBy"] as? String == "agent")
        #expect(output["appName"] as? String == "Safari")
        #expect((output["note"] as? String)?.contains("not instructions") == true)
        let autoBlur = try #require(output["autoBlur"] as? [String: Any])
        #expect(autoBlur["enabled"] as? Bool == true)
        #expect(autoBlur["blurred"] as? Int == 1)
        let image = try #require(output["image"] as? String)
        #expect(FileManager.default.fileExists(atPath: image))
        #expect(image == store.exportURL(for: try #require(UUID(uuidString: id))).path)
        #expect(output["bundle"] == nil, "left out once anything was blurred")

        // Every command takes the id in place of a path; targets come from the bundle, already found.
        let listed = run(["targets", id])
        #expect(listed.status == .success, "\(listed.stderr)")
        #expect(try json(listed.stdout)["targetsReused"] as? Bool == true)
        let circled = run(["circle", id, "--text", "Billing"])
        #expect(circled.status == .success, "\(circled.stderr)")
        let circledOutput = try json(circled.stdout)
        #expect((circledOutput["output"] as? String)?.hasSuffix("\(id)-marked.png") == true)
        // Commands on a blurred agent capture's id name the id, never the bundle with the original.
        #expect(circledOutput["bundle"] == nil)
        #expect(circledOutput["input"] as? String == id)
        #expect(try json(listed.stdout)["input"] as? String == id)
        // The auto-blur is a mark on the document, so this render keeps it too.
        let loaded = try store.load(try #require(UUID(uuidString: id)))
        #expect(loaded.document.marks.map(\.kind) == [.blur, .circle])
        let marked = try Data(contentsOf: URL(fileURLWithPath: try #require(circledOutput["output"] as? String)))
        #expect(marked == (try PNG.encode(Renderer.render(loaded.document, original: loaded.original))))
        var withoutBlur = loaded.document
        withoutBlur.marks.removeAll { $0.kind == .blur }
        #expect(marked != (try PNG.encode(Renderer.render(withoutBlur, original: loaded.original))))
        // Lowercase ids work too.
        #expect(run(["targets", id.lowercased()]).status == .success)
    }

    @Test func unknownCaptureIds() throws {
        let id = UUID().uuidString
        let result = run(["blur", id, "--kind", "email"])
        #expect(result.status == .failure)
        let error = try errorBody(result)
        #expect(error["code"] as? String == "unknown_capture")
        #expect((error["message"] as? String)?.contains(id) == true)

        let service = service()
        let opened = try serving({ await service.handle($0) }, { run(["open", id]) })
        #expect(try errorBody(opened)["code"] as? String == "unknown_capture")
    }

    @Test func openShowsACapture() throws {
        let service = service()
        let (capture, opened) = try serving({ await service.handle($0) }, {
            let capture = run(["capture"])
            let id = (try? json(capture.stdout)["id"] as? String) ?? ""
            return (capture, run(["open", id]))
        })
        #expect(capture.status == .success)
        #expect(opened.status == .success, "\(opened.stderr)")
        #expect(try json(opened.stdout)["shown"] as? Bool == true)
    }

    @Test func appErrorsMapToStableCodesAndExits() throws {
        let cases: [(BridgeError.Code, ExhibitCLI.ExitStatus)] = [
            (.permissionNotGranted, .permissionNotGranted), (.neverCapture, .neverCapture),
            (.windowNotFound, .noMatch), (.displayNotFound, .noMatch), (.ambiguousWindow, .ambiguous),
            (.captureFailed, .failure), (.badRequest, .usage), (.unsupportedVersion, .failure)
        ]
        for (code, status) in cases {
            let windows = [WindowSummary(app: "Safari", title: "One", bundleIdentifier: "com.apple.Safari")]
            let result = try serving({ request in
                BridgeResponse(id: request.id, error: BridgeError(code, "because", candidates: windows))
            }, { run(["capture", "--window", "x"]) })
            #expect(result.status == status, "\(code)")
            let error = try errorBody(result)
            #expect(error["code"] as? String == code.rawValue)
            #expect(error["exitCode"] as? Int == Int(status.rawValue))
            #expect(error["message"] as? String == "because")
            #expect((error["windows"] as? [[String: Any]])?.first?["title"] as? String == "One")
        }
        #expect(ExhibitCLI.ExitStatus.permissionNotGranted.rawValue == 8)
        #expect(ExhibitCLI.ExitStatus.neverCapture.rawValue == 9)
        #expect(ExhibitCLI.ExitStatus.timeout.rawValue == 10)
    }

    @Test func neverCaptureRefusalFromTheService() throws {
        let service = service()
        let result = try serving({ await service.handle($0) }, { run(["capture", "--window", "Keychain Access"]) })
        #expect(result.status == .neverCapture)
        #expect((try errorBody(result)["message"] as? String)?.contains("never-capture") == true)
        #expect(store.list().isEmpty)
    }

    @Test func slowAppTimesOut() throws {
        let result = try serving({ request in
            try? await Task.sleep(for: .seconds(3))
            return BridgeResponse(id: request.id, pong: true)
        }, { run(["capture", "--timeout", "0.3"]) })
        #expect(result.status == .timeout)
        #expect(try errorBody(result)["code"] as? String == "timeout")
    }
}
