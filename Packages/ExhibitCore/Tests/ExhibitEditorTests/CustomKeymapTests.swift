import ExhibitCore
@testable import ExhibitEditor
import ExhibitShell
import Foundation
import Testing

/// Issue 77: the editor's keys as data, changed in Settings and stored as differences from the defaults.
@Suite struct CustomKeymapTests {
    @Test func everyRemappableCommandHasADistinctDefault() {
        let defaults = EditorCommand.remappable.compactMap(\.defaultShortcut)
        #expect(defaults.count == EditorCommand.remappable.count)
        #expect(Set(defaults).count == defaults.count)
        #expect(EditorCommand.remappable.count == 20)
        for command in EditorCommand.fixed {
            #expect(command.defaultShortcut == nil)
            #expect(!command.isRemappable)
        }
        #expect(EditorKeymap.standard.display(for: .tool(.arrow)) == "A")
        #expect(EditorKeymap.standard.display(for: .blurAllSensitive) == "⇧B")
        #expect(EditorKeymap.standard.display(for: .copyPath) == "⇧⌘C")
        #expect(EditorKeymap.standard.display(for: .copyAndClose) == "↩")
        #expect(EditorKeymap.standard.display(for: .close) == "Esc")
        #expect(EditorKeymap.standard.display(for: .undo) == "⌘Z")
        #expect(EditorKeymap.standard.display(for: .deleteSelection) == "⌫")
    }

    @Test func idsRoundTrip() {
        for command in EditorCommand.remappable + EditorCommand.fixed {
            #expect(EditorCommand(id: command.id) == command)
        }
        #expect(EditorCommand(id: "tool.lasso") == nil)
    }

    @Test func shortcutsNormalise() {
        #expect(EditorShortcut("B", [.shift]) == EditorShortcut("b", [.shift]))
        #expect(EditorShortcut("/", [.shift]) == EditorShortcut("/"), "⇧ is part of typing symbols")
        #expect(EditorShortcut("1", [.shift]).display == "1")
        #expect(EditorShortcut(" ").display == "Space")
        #expect(EditorShortcut(key: .escape, modifiers: []) == nil)
        #expect(EditorShortcut(key: .delete, modifiers: []) == nil)
        #expect(EditorShortcut(key: .character("\t"), modifiers: []) == nil)
        #expect(EditorShortcut(key: .character("\u{F700}"), modifiers: []) == nil, "an arrow key")
        #expect(EditorShortcut(key: .returnKey, modifiers: [.command])?.display == "⌘↩")
    }

    @Test func aChangedKeyPicksTheToolAndTheOldOneNoLonger() {
        var keymap = EditorKeymap.standard
        #expect(keymap.assign(EditorShortcut("q"), to: .tool(.arrow)) == nil)
        #expect(keymap.command(for: .character("q"), modifiers: []) == .tool(.arrow))
        #expect(keymap.command(for: .character("Q"), modifiers: []) == .tool(.arrow))
        #expect(keymap.command(for: .character("a"), modifiers: []) == nil)
        #expect(keymap.display(for: .tool(.arrow)) == "Q")
        #expect(keymap.isCustom(.tool(.arrow)))
        #expect(keymap.custom == [.tool(.arrow): EditorShortcut("q")], "only the change is kept")

        keymap.reset(.tool(.arrow))
        #expect(keymap == .standard)
        #expect(keymap.command(for: .character("a"), modifiers: []) == .tool(.arrow))
    }

    @Test func assigningTheDefaultClearsTheChange() {
        var keymap = EditorKeymap.standard
        _ = keymap.assign(EditorShortcut("q"), to: .save)
        #expect(keymap.assign(EditorShortcut("s", [.command]), to: .save) == nil)
        #expect(keymap.isStandard)
    }

    @Test func aKeyAnotherCommandUsesIsRefusedByName() {
        var keymap = EditorKeymap.standard
        let issue = keymap.assign(EditorShortcut("c"), to: .tool(.arrow))
        #expect(issue == .usedBy(.tool(.circle), EditorShortcut("c")))
        #expect(issue?.message == "Circle already uses C.")
        #expect(keymap.isStandard, "a refused key changes nothing")
        #expect(keymap.assign(EditorShortcut("b", [.shift]), to: .tool(.blur))?.message
                == "Blur secrets already uses ⇧B.")
        #expect(keymap.assign(EditorShortcut("b", [.option]), to: .tool(.blur)) == nil, "⌥B is free")
    }

    @Test func fixedKeysAreRefused() {
        let keymap = EditorKeymap.standard
        #expect(keymap.issue(assigning: EditorShortcut("z", [.command]), to: .save)?.message == "⌘Z is kept for Undo.")
        #expect(keymap.issue(assigning: EditorShortcut("Z", [.command, .shift]), to: .save) == .fixed(.redo))
        #expect(keymap.issue(recording: .escape, modifiers: [], for: .save)?.message == "Esc is kept for Close.")
        #expect(keymap.issue(recording: .delete, modifiers: [], for: .save)?.message == "⌫ is kept for Delete mark.")
        #expect(keymap.issue(recording: .character("\t"), modifiers: [], for: .save) == .unsupported)
        #expect(keymap.issue(assigning: EditorShortcut("u"), to: .undo) == .notRemappable(.undo))
        #expect(keymap.issue(recording: .character("x"), modifiers: [.control], for: .save) == nil)
    }

    @Test func systemAndAppKeysAreRefusedWithTheirUse() {
        var keymap = EditorKeymap.standard
        let expected: [String: (EditorKey, KeyModifiers)] = [
            "⌘Q is kept for Quit everywhere on the Mac.": (.character("q"), [.command]),
            "⌘W is kept for Close Window everywhere on the Mac.": (.character("w"), [.command]),
            "⌘H is kept for Hide everywhere on the Mac.": (.character("H"), [.command]),
            "⌘M is kept for Minimize everywhere on the Mac.": (.character("m"), [.command]),
            "⌘, is kept for Settings everywhere on the Mac.": (.character(","), [.command]),
            "⌘Space is kept for Spotlight everywhere on the Mac.": (.character(" "), [.command]),
            "⌘` is kept for switching windows everywhere on the Mac.": (.character("`"), [.command]),
            "⌘Tab is kept for the app switcher everywhere on the Mac.": (.character("\t"), [.command])
        ]
        for (message, press) in expected {
            #expect(keymap.issue(recording: press.0, modifiers: press.1, for: .save)?.message == message)
        }
        #expect(keymap.assign(EditorShortcut("q", [.command]), to: .save) == .reserved("⌘Q", "Quit"))
        #expect(keymap.isStandard)
        #expect(keymap.issue(recording: .character("q"), modifiers: [], for: .save) == nil, "a bare Q is fine")
        #expect(keymap.issue(recording: .character("q"), modifiers: [.option], for: .save) == nil)
        #expect(EditorKeymap(stored: ["save": EditorShortcut("w", [.command])]).isStandard, "dropped on load")
    }

    @Test func resetIsRefusedWhenTheDefaultWasTaken() {
        var keymap = EditorKeymap.standard
        _ = keymap.assign(EditorShortcut("q"), to: .tool(.arrow))
        #expect(keymap.assign(EditorShortcut("a"), to: .tool(.circle)) == nil)
        #expect(keymap.reset(.tool(.arrow)) == .usedBy(.tool(.circle), EditorShortcut("a")))
        #expect(keymap.display(for: .tool(.arrow)) == "Q")
        keymap.resetAll()
        #expect(keymap == .standard)
    }

    @Test func storedChangesRoundTripThroughJSON() throws {
        var keymap = EditorKeymap.standard
        _ = keymap.assign(EditorShortcut("q"), to: .tool(.arrow))
        _ = keymap.assign(EditorShortcut("e", [.command, .option]), to: .copyPath)
        let data = try JSONEncoder().encode(keymap.stored)
        let decoded = try JSONDecoder().decode([String: EditorShortcut].self, from: data)
        #expect(EditorKeymap(stored: decoded) == keymap)
        #expect(Set(decoded.keys) == ["tool.arrow", "copyPath"])
    }

    @Test func storedSwapsLoadWhateverTheOrder() {
        // Arrow on C and Circle on A only work together; loading must not refuse the first against the default.
        let keymap = EditorKeymap(stored: ["tool.arrow": EditorShortcut("c"), "tool.circle": EditorShortcut("a")])
        #expect(keymap.command(for: .character("c"), modifiers: []) == .tool(.arrow))
        #expect(keymap.command(for: .character("a"), modifiers: []) == .tool(.circle))
    }

    @Test func damagedOrNewerStoredChangesAreDropped() {
        let keymap = EditorKeymap(stored: [
            "tool.lasso": EditorShortcut("l"),
            "save": EditorShortcut("z", [.command]),
            "tool.arrow": EditorShortcut("x"),
            "tool.circle": EditorShortcut("x")
        ])
        #expect(keymap.custom == [.tool(.arrow): EditorShortcut("x")])
    }

    @Test func aPickedKeyWinsOverADefaultThatLaterMovedOntoIt() {
        // As if a later version gave Circle the default Q after someone put Arrow on Q.
        let keymap = EditorKeymap(custom: [.tool(.arrow): EditorShortcut("c")])
        #expect(keymap.command(for: .character("c"), modifiers: []) == .tool(.arrow))
        #expect(keymap.shadowing(.tool(.circle)) == .tool(.arrow))
        #expect(keymap.shadowing(.tool(.blur)) == nil)
    }

    @Test func dictationReleasesOnItsOwnKey() {
        var keymap = EditorKeymap.standard
        #expect(keymap.releasesDictation(.character("d")))
        #expect(keymap.releasesDictation(.character("D")))
        _ = keymap.assign(EditorShortcut("g", [.option]), to: .dictate)
        #expect(!keymap.releasesDictation(.character("d")))
        #expect(keymap.releasesDictation(.character("g")), "⌥ may already be up")
        #expect(keymap.command(for: .character("g"), modifiers: [.option]) == .dictate)
        #expect(keymap.command(for: .character("d"), modifiers: []) == nil)
    }

    @MainActor @Test func theEditorUsesItsKeymap() {
        let editor = makeEditor()
        var keymap = EditorKeymap.standard
        _ = keymap.assign(EditorShortcut("q"), to: .tool(.arrow))
        _ = keymap.assign(EditorShortcut("j"), to: .dictate)
        editor.keymap = keymap
        #expect(editor.handle(.character("q")) == .handled)
        #expect(editor.tool == .arrow)
        _ = editor.handle(.character("v"))
        #expect(editor.handle(.character("a")) == .ignored)
        #expect(editor.tool == .select)
        #expect(editor.handle(.character("j")) == .app(.dictate))
        #expect(editor.handle(.character("d")) == .ignored)
    }

    @MainActor @Test func aLabelBeingTypedStillTakesRemappedKeys() {
        let editor = makeEditor()
        var keymap = EditorKeymap.standard
        _ = keymap.assign(EditorShortcut("q"), to: .tool(.arrow))
        _ = keymap.assign(EditorShortcut("k", [.shift]), to: .blurAllSensitive)
        editor.keymap = keymap
        _ = editor.handle(.character("t"))
        editor.click(PixelPoint(x: 120, y: 140))
        #expect(editor.handle(.character("q")) == .handled)
        #expect(editor.handle(.character("K"), modifiers: [.shift]) == .handled)
        #expect(editor.editingMark?.style.label == "qK")
        #expect(editor.tool == .text)
        #expect(editor.handle(.returnKey) == .handled, "↩ finishes the label")
        #expect(editor.handle(.character("q")) == .handled)
        #expect(editor.tool == .arrow)
    }

    @Test func statusLinesNameTheKeysInEffect() {
        var keymap = EditorKeymap.standard
        _ = keymap.assign(EditorShortcut("k", [.shift]), to: .blurAllSensitive)
        _ = keymap.assign(EditorShortcut("j"), to: .dictate)
        _ = keymap.assign(EditorShortcut(";"), to: .typeInstruction)
        #expect(EditorStatus.secrets(2).text(keys: keymap) == "2 possible secrets. ⇧K to blur.")
        #expect(EditorStatus.secrets(1).text == "1 possible secret. ⇧B to blur.")
        #expect(DictationStatus.listening(transcript: "").message(keys: keymap) == "Listening. Release J when done.")
        #expect(DictationStatus.microphoneDenied.message(keys: keymap).hasSuffix("or press ; to type."))
    }
}
