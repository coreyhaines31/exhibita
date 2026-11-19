import AppKit
@testable import ExhibitA
import ExhibitCore
import ExhibitEditor
import SwiftUI
import XCTest

/// 2. The spec's seven keystrokes, minus the live capture: capture and edit opens the editor, B and a click blur
/// the email, A and a drag point at the button, ↩ copies and closes.
@MainActor
final class JourneyTests: XCTestCase {
    override func setUp() async throws {
        try E2E.begin()
    }

    override func tearDown() async throws {
        E2E.closeEverything()
    }

    func testBlurPointAndCopy() async throws {
        let fixture = sampleFixture()
        let controller = try await E2E.captureAndEdit(fixture.image, scale: fixture.scale)
        let editor = try EditorDriver(controller)
        XCTAssertTrue(editor.window.isVisible)
        XCTAssertTrue(editor.window.isKeyWindow, "the editor takes the keys")
        XCTAssertTrue(NSApp.isActive)
        // What the app's layout gives on this screen: the fixture's own points (0.5 for 2x) where it fits, scaled
        // to fit otherwise, so the Dock or a small display does not change what is checked.
        let pixelSize = CGSize(width: fixture.image.width, height: fixture.image.height)
        let visible = try XCTUnwrap(editor.window.screen ?? NSScreen.main).visibleFrame
        let layoutScale = EditorLayout.pointsPerPixel(pixelSize: pixelSize, scale: fixture.scale,
                                                   available: CGSize(width: visible.width * EditorLayout.screenShare,
                                                                     height: visible.height * EditorLayout.screenShare))
        XCTAssertEqual(editor.map.pointsPerPixel, layoutScale, accuracy: 0.001, "the capture shows at the layout's scale")
        print("E2E: editor scale \(String(format: "%.3f", layoutScale)) on a \(Int(visible.width))x\(Int(visible.height)) "
              + "pt visible frame (own points: \(abs(layoutScale - 1 / fixture.scale) < 0.001))")
        // Regression: the content honoured the title bar's safe area, so the toolbar sat under a blank band and the
        // window was a title bar taller than the layout; and the divider's point was left out of the height.
        let layoutSize = EditorLayout.contentSize(pixelSize: pixelSize, pointsPerPixel: layoutScale)
        // AppKit rounds a scaled layout's fractional points to whole ones.
        let content = try XCTUnwrap(editor.window.contentView?.bounds.size)
        XCTAssertEqual(content.width, layoutSize.width, accuracy: 1, "the window is the layout's size")
        XCTAssertEqual(content.height, layoutSize.height, accuracy: 1, "the window is the layout's size")
        let canvasTop = try XCTUnwrap(controller.canvas.frameInWindow).minY
        XCTAssertEqual(canvasTop, EditorLayout.toolbarHeight + EditorLayout.dividerHeight + EditorLayout.mountPadding,
                       accuracy: 0.01, "the toolbar starts at the top, under the title bar")
        // Regression: at the old 820-point minimum the nameplate was squeezed to "E".
        let toolbar = NSHostingView(rootView: EditorToolbar(editor: controller.editor, actions: EditorActions(),
                                                            leadingInset: 74, dictation: controller.dictation))
        XCTAssertLessThanOrEqual(toolbar.fittingSize.width, EditorLayout.minimumWidth, "the whole toolbar fits")

        let email = try editor.target(.email)
        let button = try editor.target(containing: "Update plan")
        let original = Pixels(fixture.image)
        let start = ContinuousClock.now

        await editor.key("b")
        await editor.click(email.rect)
        await editor.key("a")
        await editor.drag(PixelPoint(x: button.rect.minX - 300, y: button.rect.maxY + 160),
                          PixelPoint(x: button.rect.midX, y: button.rect.midY))

        let marks = editor.editor.marks
        XCTAssertEqual(marks.map(\.kind), [.blur, .arrow], "\(marks)")
        let blur = try XCTUnwrap(marks.first { $0.kind == .blur })
        XCTAssertTrue(blur.bounds.cgRect.contains(email.rect.cgRect), "the blur covers the email")
        let arrow = try XCTUnwrap(marks.first { $0.kind == .arrow })
        guard case .line(_, let head) = arrow.geometry else { return XCTFail("an arrow is a line") }
        XCTAssertTrue(button.rect.contains(head, slack: 24), "the head \(head) is on the button \(button.rect)")
        try await editor.picture(named: "editor-after-journey")

        let pasteboard = NSPasteboard.general
        let changeCount = pasteboard.changeCount
        await editor.special(Events.returnKey)
        await E2E.wait("the copy") { pasteboard.changeCount != changeCount }
        let elapsed = ContinuousClock.now - start
        print("E2E: first key to clipboard \(elapsed.formatted(.units(allowed: [.milliseconds])))")
        XCTAssertLessThan(elapsed, .seconds(10))
        await editor.waitForClose()

        let png = try XCTUnwrap(pasteboard.data(forType: .png), "PNG on the clipboard")
        let copied = try PNG.decode(png)
        XCTAssertNotEqual(Pixels(copied).region(email.rect), original.region(email.rect), "the email is hidden")

        let saved = try E2E.store.load(editor.id)
        XCTAssertEqual(saved.document.marks.map(\.kind), [.blur, .arrow], "both marks are on disk")
        let expected = try Renderer.renderPNG(original: saved.original, marks: saved.document.marks,
                                              scale: saved.document.scale)
        XCTAssertEqual(png, expected, "the clipboard holds exactly the renderer's output")
    }
}
