import ExhibitCore
@testable import ExhibitEditor
import ExhibitShell
import ExhibitStore
import Foundation
import Testing

/// Issue 109: copy, copy and delete, and deleting an open capture so nothing can write it back.
@MainActor
@Suite struct CopyAndDeleteTests {
    let fixture = EditorFixture()

    private struct DeleteFailed: Error {}

    @Test func aFailedCopyDeletesNothing() async {
        var deleted = 0
        let outcome = await CopyAndDelete.run(copy: { false }, delete: { deleted += 1 })
        #expect(outcome == .copyFailed)
        #expect(deleted == 0)
        #expect(CopyAndDelete.message(for: outcome) == "Copying failed, nothing deleted")
    }

    @Test func aGoodCopyThenDeletes() async {
        var order: [String] = []
        let outcome = await CopyAndDelete.run(copy: { order.append("copy"); return true },
                                              delete: { order.append("delete") })
        #expect(outcome == .copiedAndDeleted)
        #expect(order == ["copy", "delete"])
        #expect(CopyAndDelete.message(for: outcome) == "Copied and deleted")
    }

    @Test func aFailedDeleteSaysSo() async {
        let outcome = await CopyAndDelete.run(copy: { true }, delete: { throw DeleteFailed() })
        #expect(outcome == .deleteFailed)
    }

    @Test func keysAndTheirDefaults() {
        let keys = EditorKeymap.standard
        #expect(keys.command(for: .character("c"), modifiers: [.command]) == .copy)
        #expect(keys.command(for: .returnKey, modifiers: [.shift]) == .copyAndDelete)
        #expect(keys.command(for: .returnKey, modifiers: []) == .copyAndClose, "↩ is still copy and close")
        #expect(keys.command(for: .character("C"), modifiers: [.command, .shift]) == .copyPath)
        #expect(keys.display(for: .copy) == "⌘C")
        #expect(keys.display(for: .copyAndDelete) == "⇧↩")
        #expect(EditorCommand.copy.isAppCommand && EditorCommand.copyAndDelete.isAppCommand)
        let order = EditorCommand.remappable
        let close = try? #require(order.firstIndex(of: .copyAndClose))
        #expect(order.firstIndex(of: .copy) == close.map { $0 - 1 })
        #expect(order.firstIndex(of: .copyAndDelete) == close.map { $0 + 1 })
        #expect(EditorCommand.copyAndDelete.detail.contains("delete the capture for good"))
        #expect(EditorCommand(id: "copyAndDelete") == .copyAndDelete)
    }

    @Test func shiftCountsOnReturnAndSpaceButNotOnSymbols() {
        #expect(EditorShortcut(EditorShortcut.returnName, [.shift]) != .returnKey)
        #expect(EditorShortcut(" ", [.shift]).display == "⇧Space")
        #expect(EditorShortcut("/", [.shift]) == EditorShortcut("/"))
        var keymap = EditorKeymap.standard
        #expect(keymap.assign(.returnKey, to: .copyAndDelete)?.message == "Copy and close already uses ↩.")
    }

    @Test func shiftReturnInALabelFinishesTheLabelAndDeletesNothing() {
        let editor = makeEditor()
        _ = editor.handle(.character("t"))
        editor.click(PixelPoint(x: 120, y: 140))
        _ = editor.handle(.character("H"), modifiers: [.shift])
        #expect(editor.handle(.returnKey, modifiers: [.shift]) == .handled)
        #expect(editor.editingTextID == nil)
        #expect(editor.marks.last?.style.label == "H")
        #expect(editor.handle(.returnKey, modifiers: [.shift]) == .app(.copyAndDelete), "outside a label it deletes")
    }

    @Test func commandCInALabelFinishesItAndCopies() {
        let editor = makeEditor()
        _ = editor.handle(.character("t"))
        editor.click(PixelPoint(x: 120, y: 140))
        _ = editor.handle(.character("x"))
        #expect(editor.handle(.character("c"), modifiers: [.command]) == .app(.copy))
        #expect(editor.editingTextID == nil)
        #expect(editor.marks.last?.style.label == "x")
    }

    @Test func deletingAnOpenCaptureLeavesNothingToWriteBack() async throws {
        let store = temporaryStore()
        defer { removeStore(store) }
        try store.prepare()
        try CaptureBundle.save(fixture.document, original: fixture.fixture.image, in: store.directory)
        let captures = OpenCaptures(store: store)
        let editor = CaptureEditor(owner: try await captures.open(fixture.document.id).owner)
        editor.press("b")
        editor.click(fixture.point(in: fixture["email"]))
        // A write is pending (100 ms debounce) when the delete is asked for.
        try await captures.delete(fixture.document.id)
        #expect(captures.capture(fixture.document.id) == nil)
        #expect(!FileManager.default.fileExists(atPath: store.url(for: fixture.document.id).path))
        // A late edit from the closing editor and a late target result must not bring it back.
        editor.press("r")
        editor.drag(from: PixelPoint(x: 10, y: 10), to: PixelPoint(x: 80, y: 60))
        captures.targetsFound(fixture.document.targets, for: fixture.document.id)
        try await Task.sleep(for: .milliseconds(400))
        captures.flushAll()
        #expect(!FileManager.default.fileExists(atPath: store.url(for: fixture.document.id).path))
        #expect(store.list().isEmpty)
    }
}
