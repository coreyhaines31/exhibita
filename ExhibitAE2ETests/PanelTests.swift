import AppKit
@testable import ExhibitA
import ExhibitCore
import XCTest

/// 7. The menu bar panel's history: newest first, select and delete, double-click and Open.
@MainActor
final class PanelTests: XCTestCase {
    override func setUp() async throws {
        try E2E.begin()
        for item in E2E.store.list() { try E2E.store.delete(item.id) }
        await E2E.model.reload()
    }

    override func tearDown() async throws {
        E2E.closeEverything()
    }

    @MainActor
    private struct Panel {
        let controller: StatusItemController
        let view: NSView
        let window: NSWindow

        /// A reported frame's centre, in window coordinates.
        func center(of name: String) throws -> NSPoint {
            let frames = controller.frames.byName
            let frame = try XCTUnwrap(frames[name], "\(name) in \(frames.keys)")
            // Frames are reported in the popover window's space; the panel's own frame says where the view starts.
            let panel = try XCTUnwrap(frames["panel"], "the panel's frame")
            let x = frame.midX - panel.minX
            let y = frame.midY - panel.minY
            return view.convert(NSPoint(x: x, y: view.isFlipped ? y : view.bounds.height - y), to: nil)
        }

        func click(_ name: String, count: Int = 1) async throws {
            try await PanelTests.ensureShown(controller)
            // Rows report their frames as they lay out (thumbnails, the selected row growing); aim only once the
            // target has stopped moving.
            var last = controller.frames.byName[name]
            for _ in 0..<12 {
                await E2E.settle(80)
                let now = controller.frames.byName[name]
                if now == last { break }
                last = now
            }
            Events.click(at: try center(of: name), in: window, count: count)
            await E2E.settle(350)
        }
    }

    /// A transient popover closes when the app stops being active, as it does just after an editor closes. A real
    /// click on the menu bar item brings the app forward; `show()` alone does not, so the test does both, and
    /// shows the panel again if it closed while the app was still deactivating.
    static func ensureShown(_ controller: StatusItemController) async throws {
        for _ in 0..<3 {
            if controller.isShown, controller.panelView?.window?.isKeyWindow == true {
                await E2E.settle(150)
                if controller.isShown { return }
            }
            NSApp.activate()
            controller.show()
            await E2E.wait("the panel") { controller.isShown }
            await E2E.settle(300)
        }
        XCTAssertTrue(controller.isShown, "the panel stays up")
    }

    private func showPanel() async throws -> Panel {
        let controller = try XCTUnwrap(E2E.app.statusItem)
        try await Self.ensureShown(controller)
        let view = try XCTUnwrap(controller.panelView)
        await E2E.wait("the rows to be laid out") { controller.frames.byName.keys.contains { $0.hasPrefix("row ") } }
        await E2E.settle(300)
        return Panel(controller: controller, view: view, window: try XCTUnwrap(view.window))
    }

    private func seedThree() throws -> [UUID] {
        let now = Date()
        let shots: [(CGImage, String, Double)] = [
            (sampleFixture().image, "Safari", 3), (teamFixture().image, "Acme Cloud", 2),
            (goldenFixture(scale: 2).image, "Settings", 1)
        ]
        return try shots.map { image, app, hours in
            try E2E.seed(image, scale: 2, appName: app, createdAt: now.addingTimeInterval(-hours * 3600), targets: [])
        }
    }

    func testHistoryNewestFirstThenDeleteAndOpen() async throws {
        let ids = try seedThree()
        await E2E.model.reload()
        XCTAssertEqual(E2E.model.items.map(\.id), ids.reversed(), "newest first")
        XCTAssertEqual(E2E.model.rows.map(\.title).first, "Settings")

        let panel = try await showPanel()
        try E2E.picture(panel.view, named: "history-panel")

        // Select the middle row, then Delete.
        let middle = ids[1]
        try await panel.click("row \(middle)")
        XCTAssertEqual(E2E.model.selected, middle, "a click selects the row")
        try await panel.click("delete \(middle)")
        await E2E.wait("the delete") { !E2E.model.items.contains { $0.id == middle } }
        XCTAssertFalse(FileManager.default.fileExists(atPath: E2E.store.url(for: middle).path), "its bundle is gone")
        XCTAssertEqual(E2E.model.items.map(\.id), [ids[2], ids[0]])

        // A double-click opens the editor.
        let oldest = ids[0]
        await E2E.settle(300)
        try await panel.click("row \(oldest)", count: 2)
        await E2E.wait("the editor from a double-click") { E2E.editors.windows[oldest]?.window?.isVisible == true }
        E2E.editors.windows[oldest]?.window?.close()
        await E2E.wait("it to close") { E2E.editors.windows[oldest] == nil }

        // Selecting a row and pressing Open opens it too.
        let newest = ids[2]
        let again = try await showPanel()
        try await again.click("row \(newest)")
        XCTAssertEqual(E2E.model.selected, newest)
        try await again.click("open \(newest)")
        await E2E.wait("the editor from Open") { E2E.editors.windows[newest]?.window?.isVisible == true }
        await E2E.wait("opening an editor to close the panel", timeout: 3) { !again.controller.isShown }
    }
}
