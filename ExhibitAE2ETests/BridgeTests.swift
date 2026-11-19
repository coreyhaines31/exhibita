import AppKit
@testable import ExhibitA
import ExhibitCore
import ExhibitTargets
import XCTest

/// 6. The real `exhibit` binary against the app's bridge, listening on the temporary support directory's socket.
@MainActor
final class BridgeTests: XCTestCase {
    private let fixture = teamFixture()

    override func setUp() async throws {
        try E2E.begin()
    }

    override func tearDown() async throws {
        E2E.closeEverything()
    }

    /// A capture in history with the targets the real finder reports, as a person's earlier capture would be.
    private func seed() async throws -> UUID {
        let targets = try await TargetFinder().findTargets(in: fixture.image)
        return try E2E.seed(fixture.image, scale: fixture.scale, appName: "Acme Cloud", targets: targets)
    }

    func testOpenShowsTheEditor() async throws {
        let id = try await seed()
        let result = try await E2E.exhibit(["open", id.uuidString])
        XCTAssertEqual(result.status, 0, result.stderr)
        XCTAssertEqual(result.json["shown"] as? Bool, true, result.stdout)
        await E2E.wait("the editor") { E2E.editors.windows[id]?.window?.isVisible == true }
        let controller = try XCTUnwrap(E2E.editors.windows[id])
        await E2E.wait("the editor to take the keys") { controller.window?.isKeyWindow == true }
        XCTAssertEqual(controller.editor.document.targets.count, try E2E.store.load(id).document.targets.count)
    }

    func testCaptureWithoutPermissionNeverPrompts() async throws {
        guard !ScreenRecording.isGranted else {
            throw XCTSkip("This build has Screen Recording; exhibit capture would capture the real screen")
        }
        let before = E2E.store.list().count
        let result = try await E2E.exhibit(["capture", "--screen"])
        XCTAssertEqual(result.status, 8, "\(result.stdout) \(result.stderr)")
        XCTAssertTrue((result.stdout + result.stderr).contains("permission_not_granted"), result.stderr)
        XCTAssertFalse(Preferences.askedForScreenRecording, "the app never asked macOS")
        XCTAssertEqual(E2E.store.list().count, before, "nothing captured")
    }

    func testBlurByKindWritesARedactedPNG() async throws {
        let id = try await seed()
        let result = try await E2E.exhibit(["blur", id.uuidString, "--kind", "email"])
        XCTAssertEqual(result.status, 0, result.stderr)
        let output = try XCTUnwrap(result.json["output"] as? String, result.stdout)
        let png = try PNG.decode(Data(contentsOf: URL(fileURLWithPath: output)))
        let email = fixture["email1"]
        XCTAssertNotEqual(Pixels(png).region(email), Pixels(fixture.image).region(email), "the email is hidden")
        let second = fixture["email2"]
        XCTAssertNotEqual(Pixels(png).region(second), Pixels(fixture.image).region(second), "both emails")
        let name = fixture["pricing"]
        XCTAssertEqual(Pixels(png).region(name), Pixels(fixture.image).region(name), "the rest is untouched")
    }
}
