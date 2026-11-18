import ExhibitCore
import ExhibitEditor
import ExhibitShell
import Testing

@Suite struct KeymapTests {
    @Test func singleKeysPickToolsAndColours() {
        let expected: [String: EditorTool] = ["a": .arrow, "c": .circle, "b": .blur, "h": .highlight, "t": .text,
                                              "r": .box, "n": .step, "v": .select]
        for (letter, tool) in expected {
            #expect(EditorKeymap.command(for: .character(letter), modifiers: []) == .tool(tool))
            #expect(EditorKeymap.command(for: .character(letter.uppercased()), modifiers: []) == .tool(tool))
        }
        #expect(EditorKeymap.command(for: .character("1"), modifiers: []) == .color(.red))
        #expect(EditorKeymap.command(for: .character("2"), modifiers: []) == .color(.yellow))
        #expect(EditorKeymap.command(for: .character("3"), modifiers: []) == .color(.blue))
        #expect(EditorKeymap.command(for: .character("4"), modifiers: []) == .color(.green))
        #expect(EditorKeymap.command(for: .character("5"), modifiers: []) == nil)
    }

    @Test func dictateIsLeftForUnitSeven() {
        #expect(EditorKeymap.command(for: .character("d"), modifiers: []) == nil)
    }

    @Test func modifiedKeys() {
        #expect(EditorKeymap.command(for: .character("B"), modifiers: [.shift]) == .blurAllSensitive)
        #expect(EditorKeymap.command(for: .character("z"), modifiers: [.command]) == .undo)
        #expect(EditorKeymap.command(for: .character("Z"), modifiers: [.command, .shift]) == .redo)
        #expect(EditorKeymap.command(for: .character("s"), modifiers: [.command]) == .save)
        #expect(EditorKeymap.command(for: .character("C"), modifiers: [.command, .shift]) == .copyPath)
        #expect(EditorKeymap.command(for: .character("a"), modifiers: [.option]) == nil)
        #expect(EditorKeymap.command(for: .character("a"), modifiers: [.shift]) == nil)
        #expect(EditorKeymap.command(for: .character("c"), modifiers: [.command]) == nil)
    }

    @Test func specialKeys() {
        #expect(EditorKeymap.command(for: .returnKey, modifiers: []) == .copyAndClose)
        #expect(EditorKeymap.command(for: .escape, modifiers: []) == .close)
        #expect(EditorKeymap.command(for: .delete, modifiers: []) == .deleteSelection)
        #expect(EditorKey.special(keyCode: 0x24) == .returnKey)
        #expect(EditorKey.special(keyCode: 0x4C) == .returnKey)
        #expect(EditorKey.special(keyCode: 0x35) == .escape)
        #expect(EditorKey.special(keyCode: 0x33) == .delete)
        #expect(EditorKey.special(keyCode: 0x00) == nil)
        #expect(EditorCommand.copyAndClose.isAppCommand)
        #expect(!EditorCommand.undo.isAppCommand)
    }

    @Test func everyToolHasItsOwnKey() {
        let keys = EditorTool.allCases.map(\.key)
        #expect(Set(keys).count == keys.count)
        #expect(EditorTool.toolbarOrder.count == EditorTool.allCases.count)
    }
}
