import AppKit
@testable import ExhibitA
import ExhibitCore
import ExhibitEditor
import XCTest

/// 9. Issue 77: editor keys changed in Settings work in the real window, the old key stops, reset brings it back,
/// a key another command has is refused, and the panel's hotkey tiles lead to Settings.
@MainActor
final class ShortcutTests: XCTestCase {
    private var fixture: Fixture!

    override func setUp() async throws {
        try E2E.begin()
        E2E.model.resetAllShortcuts()
        fixture = sampleFixture()
    }

    override func tearDown() async throws {
        E2E.closeEverything()
        E2E.model.resetAllShortcuts()
        EditorWindowController.makeTranscriber = { SpeechTranscription.make() }
        for window in NSApp.windows where window.title.hasSuffix("Settings") { window.close() }
    }

    private func open() async throws -> EditorDriver {
        try EditorDriver(await E2E.captureAndEdit(fixture.image, scale: fixture.scale))
    }

    func testARemappedToolKeyPicksTheToolAndTheOldKeyNoLonger() async throws {
        XCTAssertTrue(E2E.model.recordShortcut(.character("q"), modifiers: [], for: .tool(.arrow)))
        let editor = try await open()
        XCTAssertEqual(editor.editor.keymap.display(for: .tool(.arrow)), "Q", "a new editor reads the change")

        await editor.key("a")
        XCTAssertEqual(editor.editor.tool, .select, "A no longer picks the arrow")
        await editor.key("q")
        XCTAssertEqual(editor.editor.tool, .arrow, "Q does")
        await editor.drag(PixelPoint(x: 60, y: 500), PixelPoint(x: 300, y: 620))
        XCTAssertEqual(editor.editor.marks.last?.kind, .arrow)

        // Changed while the editor is open: it takes effect at once.
        XCTAssertTrue(E2E.model.recordShortcut(.character("j"), modifiers: [], for: .tool(.circle)))
        await editor.key("j")
        XCTAssertEqual(editor.editor.tool, .circle)
        await editor.key("c")
        XCTAssertEqual(editor.editor.tool, .circle, "C is free now and does nothing")
        try await editor.picture(named: "editor-remapped-keys")

        // Reset puts A back and frees Q.
        E2E.model.resetShortcut(.tool(.arrow))
        await editor.key("v")
        await editor.key("q")
        XCTAssertEqual(editor.editor.tool, .select, "Q is free again")
        await editor.key("a")
        XCTAssertEqual(editor.editor.tool, .arrow, "A picks the arrow again")
    }

    func testAKeyAnotherCommandUsesIsRefused() async throws {
        XCTAssertFalse(E2E.model.recordShortcut(.character("c"), modifiers: [], for: .tool(.arrow)))
        XCTAssertEqual(E2E.model.shortcutMessage(for: .tool(.arrow)), "Circle already uses C.")
        XCTAssertFalse(E2E.model.recordShortcut(.escape, modifiers: [], for: .save))
        let editor = try await open()
        await editor.key("c")
        XCTAssertEqual(editor.editor.tool, .circle, "C still picks the circle")
        await editor.key("a")
        XCTAssertEqual(editor.editor.tool, .arrow, "A still picks the arrow")
    }

    func testARemappedFinishingKeyRuns() async throws {
        XCTAssertTrue(E2E.model.recordShortcut(.character("p"), modifiers: [.command, .option], for: .copyPath))
        let editor = try await open()
        await editor.key("c", [.command, .shift])
        XCTAssertNotEqual(editor.editor.status.text, "Path copied", "the old key does nothing")
        await editor.key("p", [.command, .option])
        XCTAssertEqual(editor.editor.status.text, "Path copied")
    }

    func testHoldingARemappedDictateKeyListensUntilItComesUp() async throws {
        let fake = ReadyTranscriber(heard: "blur the emails")
        EditorWindowController.makeTranscriber = { fake }
        XCTAssertTrue(E2E.model.recordShortcut(.character("j"), modifiers: [], for: .dictate))
        let editor = try await open()
        await E2E.wait("text to be read") { editor.editor.targetsLoaded }

        Events.key("d", down: true, in: editor.window)
        Events.key("d", down: false, in: editor.window)
        await E2E.settle(200)
        XCTAssertEqual(fake.started, 0, "D no longer dictates")

        Events.key("j", down: true, in: editor.window)
        await E2E.wait("listening") { editor.controller.dictation.isListening }
        XCTAssertEqual(fake.started, 1)
        Events.key("j", down: false, in: editor.window)
        await E2E.wait("the blur") { editor.editor.marks.contains { $0.kind == .blur } }
        XCTAssertEqual(fake.finished, 1, "letting go of J stopped listening")
    }

    func testTheHotkeyTilesOpenSettings() async throws {
        let controller = try XCTUnwrap(E2E.app.statusItem)
        try await PanelTests.ensureShown(controller)
        let view = try XCTUnwrap(controller.panelView)
        await E2E.wait("the tiles to be laid out") { controller.frames.byName["hotkey captureAndEdit"] != nil }
        await E2E.settle(300)
        let frames = controller.frames.byName
        let tile = try XCTUnwrap(frames["hotkey captureAndEdit"])
        let panel = try XCTUnwrap(frames["panel"])
        let y = tile.midY - panel.minY
        let point = view.convert(NSPoint(x: tile.midX - panel.minX, y: view.isFlipped ? y : view.bounds.height - y),
                                 to: nil)
        Events.click(at: point, in: try XCTUnwrap(view.window))
        await E2E.wait("Settings") { NSApp.windows.contains { $0.title.hasSuffix("Settings") && $0.isVisible } }
        XCTAssertFalse(controller.isShown, "the panel closed for Settings")
    }
}

/// Speech that is ready at once and hears one sentence. Never touches audio.
@MainActor
private final class ReadyTranscriber: SpeechTranscribing {
    let heard: String
    var started = 0
    var finished = 0

    init(heard: String) {
        self.heard = heard
    }

    func prepare() async -> SpeechReadiness { .ready }

    func download(progress: @escaping @MainActor (Double) -> Void) async throws {}

    func start(hints: [String], partial: @escaping @MainActor (String) -> Void) async throws {
        started += 1
        partial(heard)
    }

    func finish() async -> String {
        finished += 1
        return heard
    }

    func cancel() {}
}
