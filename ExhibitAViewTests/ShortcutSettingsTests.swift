import ExhibitEditor
import ExhibitShell
import ExhibitStore
import Foundation
import XCTest

/// Settings, Shortcuts (issue 77) and the hotkey swap, through the model the views read. Preferences go to a
/// throwaway suite and history to a temporary folder; nothing is drawn.
@MainActor
final class ShortcutSettingsTests: XCTestCase {
    private var suiteName = ""
    private var captures: URL?

    override func setUp() async throws {
        suiteName = "com.exhibitaformac.tests.\(UUID().uuidString)"
        Preferences.defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        captures = FileManager.default.temporaryDirectory.appendingPathComponent(suiteName)
            .appendingPathComponent("Captures")
    }

    override func tearDown() async throws {
        Preferences.defaults.removePersistentDomain(forName: suiteName)
        Preferences.defaults = .standard
        if let captures { try? FileManager.default.removeItem(at: captures.deletingLastPathComponent()) }
    }

    private func makeModel() throws -> AppModel {
        AppModel(store: CaptureStore(directory: try XCTUnwrap(captures)), permission: .granted, system: .factory,
                 launchesAtLogin: true)
    }

    func testShortcutRowsListEveryRemappableCommandWithItsKey() throws {
        let model = try makeModel()
        XCTAssertEqual(model.shortcutRows.map(\.command), EditorCommand.remappable)
        XCTAssertEqual(model.shortcutRows.first?.key, "A")
        XCTAssertEqual(model.shortcutRows.first { $0.command == .copyPath }?.key, "⇧⌘C")
        XCTAssertTrue(model.shortcutRows.allSatisfy { !$0.isCustom && $0.message == nil && !$0.detail.isEmpty })
    }

    func testRecordingAKeyChangesTheRowStoresOnlyTheChangeAndTellsOpenEditors() throws {
        let model = try makeModel()
        var applied: [EditorKeymap] = []
        model.onKeymapChanged = { applied.append($0) }
        XCTAssertTrue(model.recordShortcut(.character("q"), modifiers: [], for: .tool(.arrow)))
        let row = try XCTUnwrap(model.shortcutRows.first { $0.command == .tool(.arrow) })
        XCTAssertEqual(row.key, "Q")
        XCTAssertTrue(row.isCustom)
        XCTAssertEqual(applied.last?.command(for: .character("q"), modifiers: []), .tool(.arrow))
        XCTAssertEqual(Preferences.editorKeymap.stored, ["tool.arrow": EditorShortcut("q")])
        let raw = try XCTUnwrap(Preferences.defaults.data(forKey: Preferences.customEditorKeysKey))
        XCTAssertEqual(try JSONDecoder().decode([String: EditorShortcut].self, from: raw).count, 1,
                       "defaults are not stored")

        let reopened = try makeModel()
        XCTAssertEqual(reopened.keymap.display(for: .tool(.arrow)), "Q", "kept across launches")

        model.resetShortcut(.tool(.arrow))
        XCTAssertEqual(model.keymap, .standard)
        XCTAssertNil(Preferences.defaults.data(forKey: Preferences.customEditorKeysKey), "nothing stored")
    }

    func testARefusedKeySaysWhichCommandHasIt() throws {
        let model = try makeModel()
        var applied = 0
        model.onKeymapChanged = { _ in applied += 1 }
        XCTAssertFalse(model.recordShortcut(.character("c"), modifiers: [], for: .tool(.arrow)))
        XCTAssertEqual(model.shortcutMessage(for: .tool(.arrow)), "Circle already uses C.")
        XCTAssertEqual(model.keymap, .standard)
        XCTAssertEqual(applied, 0)
        XCTAssertFalse(model.recordShortcut(.character("z"), modifiers: [.command], for: .save))
        XCTAssertEqual(model.shortcutMessage(for: .save), "⌘Z is kept for Undo.")
        XCTAssertTrue(model.recordShortcut(.character("x"), modifiers: [], for: .tool(.arrow)))
        XCTAssertNil(model.shortcutMessage(for: .tool(.arrow)), "the next good key clears the message")
    }

    func testResetAllPutsEveryKeyBack() throws {
        let model = try makeModel()
        model.recordShortcut(.character("q"), modifiers: [], for: .tool(.arrow))
        model.recordShortcut(.character("j"), modifiers: [], for: .dictate)
        model.recordShortcut(.character("c"), modifiers: [], for: .save)
        model.resetAllShortcuts()
        XCTAssertEqual(model.keymap, .standard)
        XCTAssertTrue(model.shortcutRows.allSatisfy { !$0.isCustom && $0.message == nil })
        XCTAssertEqual(Preferences.editorKeymap, .standard)
    }

    func testEditorKeysStayInTheTestSuite() throws {
        let model = try makeModel()
        model.recordShortcut(.character("q"), modifiers: [], for: .tool(.arrow))
        XCTAssertNotNil(Preferences.defaults.data(forKey: Preferences.customEditorKeysKey))
        XCTAssertNil(UserDefaults.standard.data(forKey: Preferences.customEditorKeysKey),
                     "never the real app's settings")
    }

    func testSwapExchangesTheHotkeys() throws {
        let model = try makeModel()
        var applied: [HotkeyBindings] = []
        model.onBindingsChanged = { applied.append($0) }
        model.swapHotkeys()
        XCTAssertEqual(model.bindings.combo(for: .captureAndEdit).display, "⌃⌥⇧4")
        XCTAssertEqual(model.bindings.combo(for: .captureToClipboard).display, "⌥⇧4")
        XCTAssertEqual(applied.count, 1, "registered again")
        XCTAssertEqual(Preferences.customHotkeys.count, 2)
        model.swapHotkeys()
        XCTAssertTrue(Preferences.customHotkeys.isEmpty)
    }
}
