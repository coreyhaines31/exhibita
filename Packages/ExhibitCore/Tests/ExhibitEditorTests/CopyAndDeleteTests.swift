import ExhibitCore
@testable import ExhibitEditor
import ExhibitShell
import ExhibitStore
import Foundation
import Testing

/// Issue 109: the copy and copy and delete keys.
@MainActor
@Suite struct CopyAndDeleteTests {
    let fixture = EditorFixture()

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
}
