import AppKit
@testable import ExhibitA
import ExhibitShell
import XCTest

/// 1. The app as it starts: a menu bar item, no window, no permission, and the hotkey's action explaining the
/// permission instead of starting a capture.
@MainActor
final class BootTests: XCTestCase {
    override func setUp() async throws {
        try E2E.begin()
    }

    override func tearDown() async throws {
        E2E.closeEverything()
    }

    func testBootsCleanAndTheHotkeyExplainsThePermission() async throws {
        // The seam reads Screen Recording as off whatever TCC says (the test host may inherit it), so nothing here
        // can capture. What macOS itself says is printed for the record.
        print("E2E: CGPreflightScreenCaptureAccess in the test host: \(CGPreflightScreenCaptureAccess())")
        XCTAssertTrue(ScreenRecording.forcedOff)
        guard !ScreenRecording.isGranted else {
            throw XCTSkip("This build has Screen Recording; the hotkey would start a real capture")
        }
        let statusItem = try XCTUnwrap(E2E.app.statusItem)
        XCTAssertNotNil(statusItem.item.button?.image, "the menu bar glyph")
        XCTAssertFalse(NSApp.windows.contains { $0.isVisible && $0.level == .normal }, "no window at launch")
        XCTAssertNotEqual(E2E.model.permission, .granted)
        XCTAssertEqual(E2E.model.content, .permission(E2E.model.permission))
        XCTAssertFalse(statusItem.isShown)

        E2E.app.hotkeyPressed(.captureAndEdit)
        await E2E.wait("the permission panel") { statusItem.isShown }
        XCTAssertFalse(E2E.app.capture!.overlay.isActive, "no selection overlay")
        XCTAssertEqual(E2E.model.permission, .notAsked, "nothing asked macOS")
        XCTAssertFalse(Preferences.askedForScreenRecording)
        XCTAssertTrue(E2E.editors.windows.isEmpty)
        await E2E.settle(400)
        let panel = try XCTUnwrap(statusItem.panelView, "the panel's view")
        try E2E.picture(panel, named: "permission-panel")
    }
}
