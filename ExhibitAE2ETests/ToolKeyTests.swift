import AppKit
@testable import ExhibitA
import ExhibitCore
import ExhibitEditor
import XCTest

/// 3. Every key in the editor's Keys table, pressed as keys in the real window.
@MainActor
final class ToolKeyTests: XCTestCase {
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

    func testDrawingToolsAndColours() async throws {
        let editor = try await open()
        let renews = try editor.target(containing: "Renews")
        let seats = try editor.target(containing: "Includes")

        await editor.key("c")
        await editor.click(renews.rect)
        await editor.key("h")
        await editor.click(seats.rect)
        await editor.key("r")
        await editor.drag(PixelPoint(x: 40, y: 500), PixelPoint(x: 340, y: 600))
        XCTAssertEqual(editor.editor.marks.map(\.kind), [.circle, .highlight, .box])
        guard editor.editor.marks.count == 3 else { return }
        let circle = editor.editor.marks[0]
        XCTAssertTrue(circle.bounds.cgRect.contains(renews.rect.cgRect), "the circle snapped around the line")
        XCTAssertEqual(editor.editor.marks[1].targetID, seats.id, "the highlight snapped to the line")
        let box = editor.editor.marks[2].bounds
        XCTAssertEqual(box.minX, 40, accuracy: 2)
        XCTAssertEqual(box.maxY, 600, accuracy: 2)

        // T: a click places a label, typing fills it, Return finishes it without closing the window.
        await editor.key("t")
        await editor.click(PixelPoint(x: 60, y: 700))
        XCTAssertNotNil(editor.editor.editingTextID, "typing into a new label")
        await editor.type("Ship it")
        await editor.special(Events.returnKey)
        XCTAssertNil(editor.editor.editingTextID)
        XCTAssertTrue(editor.window.isVisible, "Return finished the label, not the capture")
        XCTAssertEqual(editor.editor.marks.last?.style.label, "Ship it")

        // N three times numbers 1, 2, 3.
        await editor.key("n")
        for x in [80.0, 180, 280] { await editor.click(PixelPoint(x: x, y: 820)) }
        XCTAssertEqual(editor.editor.marks.filter { $0.kind == .step }.compactMap(\.style.stepNumber), [1, 2, 3])

        // 1 to 4 pick the colour of the next mark.
        let colours: [(Character, MarkColor)] = [("1", .red), ("2", .yellow), ("3", .blue), ("4", .green)]
        for (index, (key, colour)) in colours.enumerated() {
            await editor.key("r")
            await editor.key(key)
            let left = 460 + Double(index) * 160
            await editor.drag(PixelPoint(x: left, y: 880), PixelPoint(x: left + 120, y: 940))
            XCTAssertEqual(editor.editor.marks.last?.style.color, colour, "key \(key)")
        }
        try await editor.picture(named: "editor-every-tool")
    }

    func testSelectMoveAndDelete() async throws {
        let editor = try await open()
        await editor.key("r")
        await editor.drag(PixelPoint(x: 40, y: 500), PixelPoint(x: 300, y: 700))
        let drawn = try XCTUnwrap(editor.editor.marks.first)

        await editor.key("v")
        await editor.click(PixelPoint(x: 40, y: 600))
        XCTAssertEqual(editor.editor.selectedID, drawn.id, "V and a click select the box's edge")
        await editor.drag(PixelPoint(x: 40, y: 600), PixelPoint(x: 140, y: 560))
        let moved = try XCTUnwrap(editor.editor.marks.first).bounds
        XCTAssertEqual(moved.minX, drawn.bounds.minX + 100, accuracy: 2, "moved right")
        XCTAssertEqual(moved.minY, drawn.bounds.minY - 40, accuracy: 2, "moved up")
        XCTAssertEqual(moved.width, drawn.bounds.width, accuracy: 0.5, "not resized")

        await editor.special(Events.delete)
        XCTAssertTrue(editor.editor.marks.isEmpty, "Delete removes the selected mark")
    }

    func testUndoRedoAndBlurEverySecret() async throws {
        let editor = try await open()
        await editor.key("r")
        await editor.drag(PixelPoint(x: 40, y: 500), PixelPoint(x: 300, y: 700))
        await editor.drag(PixelPoint(x: 40, y: 760), PixelPoint(x: 300, y: 900))
        XCTAssertEqual(editor.editor.marks.count, 2)
        await editor.key("z", .command)
        XCTAssertEqual(editor.editor.marks.count, 1, "⌘Z")
        await editor.key("z", .command)
        XCTAssertEqual(editor.editor.marks.count, 0, "⌘Z again")
        await editor.key("z", [.command, .shift])
        XCTAssertEqual(editor.editor.marks.count, 1, "⇧⌘Z")

        let secrets = editor.editor.uncoveredSecrets
        XCTAssertEqual(Set(secrets.map(\.kind)), [.email, .key], "the email and the key")
        await editor.key("b", .shift)
        let blurs = editor.editor.marks.filter { $0.kind == .blur }
        XCTAssertEqual(blurs.count, secrets.count, "⇧B blurs every secret")
        XCTAssertEqual(editor.editor.status.text, "Blurred 2 possible secrets")
        await editor.key("z", .command)
        XCTAssertEqual(editor.editor.marks.count, 1, "one ⌘Z takes back every blur ⇧B added")
    }

    func testEscapeClosesAndKeepsTheCapture() async throws {
        let editor = try await open()
        await editor.key("r")
        await editor.drag(PixelPoint(x: 40, y: 500), PixelPoint(x: 300, y: 700))
        let pasteboard = NSPasteboard.general.changeCount
        await editor.special(Events.escape)
        await editor.waitForClose()
        XCTAssertEqual(NSPasteboard.general.changeCount, pasteboard, "Esc copies nothing")
        let saved = try E2E.store.load(editor.id)
        XCTAssertEqual(saved.document.marks.count, 1, "the capture and its mark stay in history")
        await E2E.wait("history to list it") { E2E.model.items.contains { $0.id == editor.id } }
    }

    func testCopyPathWritesTheFile() async throws {
        let editor = try await open()
        await editor.key("b", .shift)
        await editor.key("c", [.command, .shift])
        let path = try XCTUnwrap(NSPasteboard.general.string(forType: .string), "a path on the clipboard")
        XCTAssertTrue(path.hasPrefix(try XCTUnwrap(TestSeam.exportsFolder).path), path)
        XCTAssertTrue(path.hasSuffix("-marked.png"), path)
        let written = try Data(contentsOf: URL(fileURLWithPath: path))
        let expected = try EditorExport.png(editor.editor.document, original: fixture.image)
        XCTAssertEqual(written, expected, "the file is the renderer's output")
        XCTAssertEqual(editor.editor.status.text, "Path copied")
        XCTAssertTrue(editor.window.isVisible, "the editor stays open")
    }

    func testSaveShowsTheSheet() async throws {
        // The save panel writes its last folder into the app's own settings: only under the e2e identity.
        guard Bundle.main.bundleIdentifier?.hasSuffix(".e2e") == true else {
            throw XCTSkip("Run through Scripts/run-e2e.sh, so the save panel never writes the real app's settings")
        }
        let editor = try await open()
        await editor.key("s", .command)
        await E2E.wait("the save sheet") { editor.window.attachedSheet != nil }
        let sheet = try XCTUnwrap(editor.window.attachedSheet)
        XCTAssertTrue(sheet is NSSavePanel, "\(type(of: sheet))")
        XCTAssertTrue((sheet as? NSSavePanel)?.nameFieldStringValue.hasSuffix("-marked.png") == true)
        editor.window.endSheet(sheet, returnCode: .cancel)
        await E2E.wait("the sheet to go") { editor.window.attachedSheet == nil }
        XCTAssertTrue(editor.window.isVisible)
        XCTAssertNotEqual(editor.editor.status.text, "Saved")
    }
}
