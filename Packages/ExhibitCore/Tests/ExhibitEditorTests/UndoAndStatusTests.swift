import ExhibitCore
@testable import ExhibitEditor
import ExhibitShell
import Testing

@MainActor
@Suite struct UndoAndStatusTests {
    let fixture = EditorFixture()

    @Test func eachActionIsOneUndoStepAndRedoReplaysIt() {
        let editor = makeEditor(fixture)
        editor.press("r")
        editor.drag(from: PixelPoint(x: 10, y: 10), to: PixelPoint(x: 100, y: 100))
        editor.press("n")
        editor.click(PixelPoint(x: 300, y: 300))
        let both = editor.marks
        #expect(both.count == 2)

        #expect(editor.handle(.character("z"), modifiers: [.command]) == .handled)
        #expect(editor.marks.map(\.kind) == [.box])
        editor.undo()
        #expect(editor.marks.isEmpty)
        #expect(!editor.canUndo)
        editor.undo()
        #expect(editor.marks.isEmpty)

        #expect(editor.handle(.character("Z"), modifiers: [.command, .shift]) == .handled)
        editor.redo()
        #expect(editor.marks == both)
        #expect(!editor.canRedo)
    }

    @Test func aNewChangeClearsRedo() {
        let editor = makeEditor(fixture)
        editor.press("n")
        editor.click(PixelPoint(x: 100, y: 100))
        editor.undo()
        #expect(editor.canRedo)
        editor.click(PixelPoint(x: 200, y: 100))
        #expect(!editor.canRedo)
    }

    @Test func shiftBBlursEverySecretAsOneStep() {
        let editor = makeEditor(fixture)
        #expect(editor.status == .secrets(2))
        #expect(editor.status.text == "2 possible secrets. ⇧B to blur.")
        #expect(editor.handle(.character("B"), modifiers: [.shift]) == .handled)
        #expect(Set(editor.marks.compactMap(\.targetID)) == [fixture.emailID, fixture.keyID])
        #expect(editor.marks.allSatisfy { $0.kind == .blur })
        #expect(editor.status == .notice("Blurred 2 possible secrets"))
        editor.press("v")
        #expect(editor.status == .none, "nothing left uncovered")
        editor.undo()
        #expect(editor.marks.isEmpty, "one ⌘Z removes the whole batch")
    }

    @Test func shiftBSkipsSecretsAlreadyCovered() {
        let editor = makeEditor(fixture)
        editor.press("b")
        // A hand-dragged blur that covers the email counts, even with no target id.
        let email = fixture["email"]
        editor.drag(from: PixelPoint(x: email.minX - 10, y: email.minY - 10),
                    to: PixelPoint(x: email.maxX + 10, y: email.maxY + 10))
        #expect(editor.status == .secrets(1))
        #expect(editor.status.text == "1 possible secret. ⇧B to blur.")
        #expect(editor.blurAllSensitive() == 1)
        #expect(editor.marks.count == 2)
        #expect(editor.marks.last?.targetID == fixture.keyID)
        #expect(editor.blurAllSensitive() == 0)
        #expect(editor.status == .notice("No secrets to blur"))
    }

    @Test func aBatchFromElsewhereIsOneStep() {
        let editor = makeEditor(fixture)
        let changed = editor.transact { marks in
            marks.append(.circle(PixelRect(x: 1, y: 1, width: 10, height: 10)))
            marks.append(.box(PixelRect(x: 20, y: 1, width: 10, height: 10)))
            marks.append(.blur(PixelRect(x: 40, y: 1, width: 10, height: 10)))
        }
        #expect(changed)
        #expect(!editor.transact { _ in }, "no change, no undo step")
        editor.undo()
        #expect(editor.marks.isEmpty)
    }

    @Test func whileTextIsLoadingSnappingAndShiftBSayReadingText() {
        let editor = makeEditor(EditorFixture(withTargets: false), targetsLoaded: false)
        #expect(editor.status == .readingText)
        #expect(editor.status.text == "Reading text")
        editor.press("b")
        editor.click(PixelPoint(x: 500, y: 600))
        #expect(editor.marks.isEmpty)
        #expect(editor.status == .notice("Reading text"))
        #expect(editor.blurAllSensitive() == 0)

        // Drawing by hand works at once.
        editor.drag(from: PixelPoint(x: 10, y: 10), to: PixelPoint(x: 100, y: 40))
        #expect(editor.marks.count == 1)
        #expect(editor.status == .readingText)

        // Targets arrive through the owner; the hand-drawn mark stays.
        editor.owner.mergeTargets(fixture.document.targets)
        #expect(editor.status == .secrets(2))
        #expect(editor.marks.count == 1)
        editor.click(fixture.point(in: fixture["email"]))
        #expect(editor.marks.last?.targetID == fixture.emailID)
    }

    @Test func undoKeepsWorkingAfterTargetsArrive() {
        let editor = makeEditor(EditorFixture(withTargets: false), targetsLoaded: false)
        editor.press("r")
        editor.drag(from: PixelPoint(x: 10, y: 10), to: PixelPoint(x: 100, y: 40))
        editor.owner.mergeTargets(fixture.document.targets)
        editor.undo()
        #expect(editor.marks.isEmpty)
        #expect(editor.document.targets == fixture.document.targets, "undo is about marks; targets stay")
    }

    @Test func appKeysAreHandedBack() {
        let editor = makeEditor(fixture)
        #expect(editor.handle(.returnKey) == .app(.copyAndClose))
        #expect(editor.handle(.escape) == .app(.close))
        #expect(editor.handle(.character("s"), modifiers: [.command]) == .app(.save))
        #expect(editor.handle(.character("c"), modifiers: [.command, .shift]) == .app(.copyPath))
        #expect(editor.handle(.character("d")) == .ignored)
        #expect(editor.handle(.character("q"), modifiers: [.control]) == .ignored)
    }
}
