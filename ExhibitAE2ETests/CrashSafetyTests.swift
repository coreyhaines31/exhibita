import AppKit
@testable import ExhibitA
import ExhibitCore
import XCTest

/// 5. A hard stop: marks made, the window never closed and nothing flushed. After the 100 ms debounce, the
/// bundle on disk already holds them, so a crash or a kill loses nothing.
@MainActor
final class CrashSafetyTests: XCTestCase {
    override func setUp() async throws {
        try E2E.begin()
    }

    override func tearDown() async throws {
        E2E.closeEverything()
    }

    func testMarksAreOnDiskWithoutClosing() async throws {
        let fixture = sampleFixture()
        let editor = try EditorDriver(await E2E.captureAndEdit(fixture.image, scale: fixture.scale))
        await editor.key("r")
        await editor.drag(PixelPoint(x: 40, y: 500), PixelPoint(x: 300, y: 700))
        await editor.key("b", .shift)
        let made = editor.editor.marks
        XCTAssertEqual(made.count, 3, "a box and two blurs")

        // Past the debounce; no close, no flush, as if the process were killed now.
        await E2E.settle(400)
        let reloaded = try CaptureBundle.load(from: E2E.store.url(for: editor.id))
        XCTAssertEqual(reloaded.document.marks, made, "every mark is already written")
        XCTAssertFalse(reloaded.document.targets.isEmpty, "and the targets found")
    }
}
