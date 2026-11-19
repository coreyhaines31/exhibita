import AppKit
@testable import ExhibitA
import SwiftUI
import XCTest

/// Issue 94: the panel's Check for Updates reaches the updater's `checkNow`, and builds without a configured updater
/// (this test host) show the version only.
@MainActor
final class UpdateFooterTests: XCTestCase {
    private var window: NSWindow?

    override func setUp() async throws {
        try E2E.begin()
    }

    override func tearDown() async throws {
        window?.orderOut(nil)
        window = nil
        E2E.closeEverything()
    }

    func testCheckForUpdatesInThePanelCallsTheUpdater() async throws {
        var checks = 0
        let frames = PanelFrames()
        var actions = PanelActions()
        actions.reportFrame = { frames.byName[$0] = $1 }
        let updates = UpdateSettings(isConfigured: true, version: "9.9.9", checkNow: { checks += 1 })
        let hosting = NSHostingView(rootView: PanelView(model: E2E.model, actions: actions, updates: updates))
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        window.isReleasedWhenClosed = false
        window.orderFront(nil)
        self.window = window
        await E2E.wait("the button to be laid out") { frames.byName["check for updates"] != nil }
        await E2E.settle(200)

        let button = try XCTUnwrap(frames.byName["check for updates"])
        let panel = try XCTUnwrap(frames.byName["panel"])
        let y = button.midY - panel.minY
        let point = hosting.convert(NSPoint(x: button.midX - panel.minX,
                                            y: hosting.isFlipped ? y : hosting.bounds.height - y), to: nil)
        Events.click(at: point, in: window)
        await E2E.wait("the check") { checks == 1 }
        XCTAssertEqual(checks, 1, "one click, one check")
    }

    func testTheRealPanelShowsNoCheckWithoutAConfiguredUpdater() async throws {
        XCTAssertFalse(Updater.isConfigured, "the test seam keeps Sparkle off")
        let controller = try XCTUnwrap(E2E.app.statusItem)
        try await PanelTests.ensureShown(controller)
        await E2E.wait("the panel to lay out") { controller.frames.byName["panel"] != nil }
        await E2E.settle(300)
        XCTAssertNil(controller.frames.byName["check for updates"], "version only")
    }
}
