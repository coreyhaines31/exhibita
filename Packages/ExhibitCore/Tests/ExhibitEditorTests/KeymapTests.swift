import ExhibitCore
@testable import ExhibitEditor
import ExhibitShell
import Testing

@Suite struct KeymapTests {
    @Test func singleKeysPickToolsAndColours() {
        let expected: [String: EditorTool] = ["a": .arrow, "c": .circle, "b": .blur, "h": .highlight, "t": .text,
                                              "r": .box, "n": .step, "v": .select]
        for (letter, tool) in expected {
            #expect(EditorKeymap.standard.command(for: .character(letter), modifiers: []) == .tool(tool))
            #expect(EditorKeymap.standard.command(for: .character(letter.uppercased()), modifiers: []) == .tool(tool))
        }
        #expect(EditorKeymap.standard.command(for: .character("1"), modifiers: []) == .color(.red))
        #expect(EditorKeymap.standard.command(for: .character("2"), modifiers: []) == .color(.yellow))
        #expect(EditorKeymap.standard.command(for: .character("3"), modifiers: []) == .color(.blue))
        #expect(EditorKeymap.standard.command(for: .character("4"), modifiers: []) == .color(.green))
        #expect(EditorKeymap.standard.command(for: .character("5"), modifiers: []) == nil)
    }

    @Test func dHeldDictatesAndSlashTypes() {
        #expect(EditorKeymap.standard.command(for: .character("d"), modifiers: []) == .dictate)
        #expect(EditorKeymap.standard.command(for: .character("D"), modifiers: []) == .dictate)
        #expect(EditorKeymap.standard.command(for: .character("d"), modifiers: [.command]) == nil)
        #expect(EditorKeymap.standard.command(for: .character("/"), modifiers: []) == .typeInstruction)
        #expect(EditorKeymap.standard.command(for: .character("/"), modifiers: [.shift]) == .typeInstruction,
                "layouts where / needs ⇧")
        #expect(EditorCommand.dictate.isAppCommand)
        #expect(EditorCommand.typeInstruction.isAppCommand)
    }

    @MainActor @Test func dInALabelBeingTypedIsTheLetter() {
        let editor = makeEditor()
        _ = editor.handle(.character("t"))
        editor.click(PixelPoint(x: 120, y: 140))
        #expect(editor.handle(.character("d")) == .handled)
        #expect(editor.handle(.character("/")) == .handled)
        #expect(editor.editingMark?.style.label == "d/")
        #expect(editor.handle(.returnKey) == .handled)
        #expect(editor.handle(.character("d")) == .app(.dictate))
    }

    @Test func modifiedKeys() {
        #expect(EditorKeymap.standard.command(for: .character("B"), modifiers: [.shift]) == .blurAllSensitive)
        #expect(EditorKeymap.standard.command(for: .character("z"), modifiers: [.command]) == .undo)
        #expect(EditorKeymap.standard.command(for: .character("Z"), modifiers: [.command, .shift]) == .redo)
        #expect(EditorKeymap.standard.command(for: .character("s"), modifiers: [.command]) == .save)
        #expect(EditorKeymap.standard.command(for: .character("C"), modifiers: [.command, .shift]) == .copyPath)
        #expect(EditorKeymap.standard.command(for: .character("a"), modifiers: [.option]) == nil)
        #expect(EditorKeymap.standard.command(for: .character("a"), modifiers: [.shift]) == nil)
        #expect(EditorKeymap.standard.command(for: .character("c"), modifiers: [.command]) == .copy)
    }

    @Test func specialKeys() {
        #expect(EditorKeymap.standard.command(for: .returnKey, modifiers: []) == .copyAndClose)
        #expect(EditorKeymap.standard.command(for: .escape, modifiers: []) == .close)
        #expect(EditorKeymap.standard.command(for: .delete, modifiers: []) == .deleteSelection)
        #expect(EditorKey.special(keyCode: 0x24) == .returnKey)
        #expect(EditorKey.special(keyCode: 0x4C) == .returnKey)
        #expect(EditorKey.special(keyCode: 0x35) == .escape)
        #expect(EditorKey.special(keyCode: 0x33) == .delete)
        #expect(EditorKey.special(keyCode: 0x00) == nil)
        #expect(EditorCommand.copyAndClose.isAppCommand)
        #expect(!EditorCommand.undo.isAppCommand)
    }

    @Test func everyToolHasItsOwnKey() {
        let keys = EditorTool.allCases.map(\.defaultKey)
        #expect(Set(keys).count == keys.count)
        #expect(EditorTool.toolbarOrder.count == EditorTool.allCases.count)
    }
}
