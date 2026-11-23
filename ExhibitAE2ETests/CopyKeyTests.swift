import AppKit
@testable import ExhibitA
import ExhibitCore
import ExhibitEditor
import XCTest

/// Issue 109: ⌘C copies and keeps the editor open; ⇧↩ copies, closes and deletes the capture for good.
@MainActor
final class CopyKeyTests: XCTestCase {
    private var fixture: Fixture!

    override func setUp() async throws {
        try E2E.begin()
        fixture = sampleFixture()
    }

    override func tearDown() async throws {
        E2E.closeEverything()
    }

    private func open() async throws -> EditorDriver {
        try EditorDriver(await E2E.captureAndEdit(fixture.image, scale: fixture.scale))
    }

    func testCommandCCopiesAndKeepsTheEditorOpen() async throws {
        let editor = try await open()
        await editor.key("r")
        await editor.drag(PixelPoint(x: 40, y: 500), PixelPoint(x: 300, y: 700))
        await editor.key("c", .command)
        let expected = try EditorExport.png(editor.editor.document, original: fixture.image)
        XCTAssertEqual(NSPasteboard.general.data(forType: .png), expected, "the marked-up image")
        XCTAssertEqual(editor.editor.status.text, "Copied")
        XCTAssertTrue(editor.window.isVisible, "the editor stays open")
        XCTAssertTrue(FileManager.default.fileExists(atPath: E2E.store.url(for: editor.id).path))
    }

    func testShiftReturnCopiesClosesAndDeletes() async throws {
        let editor = try await open()
        let id = editor.id
        await editor.key("r")
        await editor.drag(PixelPoint(x: 40, y: 500), PixelPoint(x: 300, y: 700))
        let expected = try EditorExport.png(editor.editor.document, original: fixture.image)
        let notes = try XCTUnwrap(E2E.app.capture).copiedNote.shown
        await editor.special(Events.returnKey, .shift)
        await E2E.wait("the editor to close") { E2E.editors.windows[id] == nil && !editor.window.isVisible }
        XCTAssertEqual(NSPasteboard.general.data(forType: .png), expected, "copied before anything was deleted")
        // Past the writer's 100 ms debounce, nothing has written the capture back.
        try await Task.sleep(for: .milliseconds(400))
        E2E.editors.flushAll()
        XCTAssertFalse(FileManager.default.fileExists(atPath: E2E.store.url(for: id).path), "no bundle on disk")
        await E2E.wait("history to drop it") { !E2E.model.items.contains { $0.id == id } }
        let note = try XCTUnwrap(E2E.app.capture).copiedNote
        XCTAssertEqual(note.shown, notes + 1)
        XCTAssertEqual(note.lastText, "Copied and deleted")
    }

    func testShiftReturnInALabelOnlyFinishesTheLabel() async throws {
        let editor = try await open()
        await editor.key("t")
        await editor.click(PixelPoint(x: 60, y: 700))
        await editor.type("Ship")
        await editor.special(Events.returnKey, .shift)
        XCTAssertNil(editor.editor.editingTextID)
        XCTAssertTrue(editor.window.isVisible, "still open")
        XCTAssertTrue(FileManager.default.fileExists(atPath: E2E.store.url(for: editor.id).path), "not deleted")
    }
}
