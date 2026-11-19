import ExhibitCore
@testable import ExhibitEditor
import ExhibitShell
import Testing

@MainActor
@Suite struct GestureTests {
    let fixture = EditorFixture()

    @Test func blurClickOnAnEmailCoversExactlyThatTarget() throws {
        let editor = makeEditor(fixture)
        editor.press("b")
        editor.click(fixture.point(in: fixture["email"]))
        let mark = try #require(editor.marks.only)
        #expect(mark.kind == .blur)
        #expect(mark.targetID == fixture.emailID)
        #expect(mark.bounds == fixture["email"])
        #expect(editor.selectedID == mark.id)
    }

    @Test func highlightClickCoversTheWholeRunFromItsWordBoxes() throws {
        let editor = makeEditor(fixture)
        editor.press("h")
        // A click on the last word still covers the whole line.
        let renews = fixture["renews"]
        editor.click(PixelPoint(x: renews.maxX - 4, y: renews.midY))
        let mark = try #require(editor.marks.only)
        #expect(mark.kind == .highlight)
        #expect(mark.targetID == fixture.renewsID)
        #expect(mark.style.color == .yellow)
        #expect(abs(mark.bounds.minX - renews.minX) < 0.001)
        #expect(abs(mark.bounds.maxX - renews.maxX) < 0.001)
    }

    @Test func blurClickOnPlainTextCoversTheLine() throws {
        let editor = makeEditor(fixture)
        editor.press("b")
        editor.click(fixture.point(in: fixture["renews"]))
        let mark = try #require(editor.marks.only)
        #expect(mark.bounds == fixture["renews"], "the detector's box, never a tighter one")
    }

    @Test func clickOnNothingSaysSoAndAddsNothing() {
        let editor = makeEditor(fixture)
        editor.press("b")
        editor.click(PixelPoint(x: 5, y: 900))
        #expect(editor.marks.isEmpty)
        #expect(editor.status == .notice("No text here. Drag to draw."))
    }

    @Test func dragDrawsWhatWasDragged() throws {
        let editor = makeEditor(fixture)
        let start = PixelPoint(x: 700, y: 500)
        let end = PixelPoint(x: 600, y: 420)
        for (letter, kind) in [("r", MarkKind.box), ("c", .circle), ("b", .blur), ("h", .highlight)] {
            editor.press(letter)
            editor.pointerDown(at: start)
            editor.pointerDragged(to: end)
            #expect(editor.draft?.kind == kind)
            editor.pointerUp(at: end)
            #expect(editor.draft == nil)
            let mark = try #require(editor.marks.last)
            #expect(mark.kind == kind)
            #expect(mark.bounds == PixelRect(x: 600, y: 420, width: 100, height: 80))
            #expect(mark.targetID == nil)
        }
        #expect(editor.marks.count == 4)
    }

    @Test func circleAndBoxClickSnapAroundTheTarget() throws {
        let editor = makeEditor(fixture)
        editor.press("c")
        editor.click(fixture.point(in: fixture["update"]))
        editor.press("r")
        editor.click(fixture.point(in: fixture["key"]))
        #expect(editor.marks.map(\.kind) == [.circle, .box])
        #expect(editor.marks[0].targetID == fixture.updateID)
        #expect(editor.marks[0].bounds == fixture["update"])
        #expect(editor.marks[1].targetID == fixture.keyID)
    }

    @Test func arrowDragSnapsItsHeadToTheTargetUnderIt() throws {
        let editor = makeEditor(fixture)
        editor.press("a")
        let tail = PixelPoint(x: 900, y: 700)
        let update = fixture["update"]
        editor.drag(from: tail, to: fixture.point(in: update))
        let mark = try #require(editor.marks.only)
        guard case let .line(from, to) = mark.geometry else {
            Issue.record("not a line")
            return
        }
        #expect(from == tail)
        #expect(mark.targetID == fixture.updateID)
        // The head stops just outside the button, on the side facing the tail.
        let inside = to.x > update.minX && to.x < update.maxX && to.y > update.minY && to.y < update.maxY
        #expect(!inside)
        #expect(to.y > update.maxY)
    }

    @Test func arrowDragOffAnyTargetEndsWhereReleased() throws {
        let editor = makeEditor(fixture)
        editor.press("a")
        editor.drag(from: PixelPoint(x: 10, y: 900), to: PixelPoint(x: 200, y: 800))
        #expect(editor.marks.only?.geometry == .line(from: PixelPoint(x: 10, y: 900), to: PixelPoint(x: 200, y: 800)))
    }

    @Test func arrowClickOnATargetPicksATail() throws {
        let editor = makeEditor(fixture)
        editor.press("a")
        editor.click(fixture.point(in: fixture["update"]))
        let mark = try #require(editor.marks.only)
        #expect(mark.kind == .arrow)
        #expect(mark.targetID == fixture.updateID)
    }

    @Test func stepsCountUpByThemselves() {
        let editor = makeEditor(fixture)
        editor.press("n")
        editor.click(PixelPoint(x: 100, y: 100))
        editor.click(PixelPoint(x: 200, y: 100))
        editor.click(PixelPoint(x: 300, y: 100))
        #expect(editor.marks.map { $0.style.stepNumber } == [1, 2, 3])
        editor.undo()
        editor.click(PixelPoint(x: 400, y: 100))
        #expect(editor.marks.map { $0.style.stepNumber } == [1, 2, 3])
    }

    @Test func textClickPlacesALabelThenTypingEditsIt() {
        let editor = makeEditor(fixture)
        editor.press("t")
        editor.click(PixelPoint(x: 120, y: 140))
        #expect(editor.editingTextID != nil)
        // Letters are typed, not tools, while a label is open.
        editor.press("Bad")
        #expect(editor.handle(.delete) == .handled)
        editor.press(" ab", [.shift])
        #expect(editor.handle(.returnKey) == .handled, "↩ commits the label, it does not copy and close")
        #expect(editor.editingTextID == nil)
        #expect(editor.marks.only?.style.label == "Ba ab")
        #expect(editor.tool == .text)
        // One undo removes the label with its typing.
        editor.undo()
        #expect(editor.marks.isEmpty)
    }

    @Test func emptyLabelLeavesNothingBehind() {
        let editor = makeEditor(fixture)
        editor.press("t")
        editor.click(PixelPoint(x: 120, y: 140))
        #expect(editor.handle(.escape) == .handled)
        #expect(editor.marks.isEmpty)
        #expect(!editor.canUndo)
    }

    @Test func commandKeysFinishALabelFirst() {
        let editor = makeEditor(fixture)
        editor.press("t")
        editor.click(PixelPoint(x: 120, y: 140))
        editor.press("Hi")
        #expect(editor.handle(.character("s"), modifiers: [.command]) == .app(.save))
        #expect(editor.editingTextID == nil)
        #expect(editor.marks.only?.style.label == "Hi")
    }

    @Test func coloursApplyToNewMarksAndTheSelection() {
        let editor = makeEditor(fixture)
        editor.press("r")
        editor.drag(from: PixelPoint(x: 10, y: 10), to: PixelPoint(x: 100, y: 100))
        #expect(editor.marks[0].style.color == .red)
        editor.press("3")
        #expect(editor.marks[0].style.color == .blue, "the just-drawn mark is selected")
        editor.press("h")
        #expect(editor.currentColor == .blue)
        editor.drag(from: PixelPoint(x: 200, y: 10), to: PixelPoint(x: 300, y: 50))
        #expect(editor.marks[1].style.color == .blue)
    }

    @Test func selectMoveResizeAndDelete() throws {
        let editor = makeEditor(fixture)
        editor.press("r")
        editor.drag(from: PixelPoint(x: 100, y: 100), to: PixelPoint(x: 200, y: 160))
        let id = try #require(editor.marks.only?.id)

        editor.press("v")
        editor.click(PixelPoint(x: 5, y: 5))
        #expect(editor.selectedID == nil)
        // Grab the box's edge and move it.
        editor.drag(from: PixelPoint(x: 100, y: 130), to: PixelPoint(x: 150, y: 150))
        #expect(editor.selectedID == id)
        #expect(editor.marks.only?.bounds == PixelRect(x: 150, y: 120, width: 100, height: 60))

        // Drag the bottom-right handle.
        editor.drag(from: PixelPoint(x: 250, y: 180), to: PixelPoint(x: 300, y: 200))
        #expect(editor.marks.only?.bounds == PixelRect(x: 150, y: 120, width: 150, height: 80))

        #expect(editor.handle(.delete) == .handled)
        #expect(editor.marks.isEmpty)
        editor.undo()
        #expect(editor.marks.only?.bounds == PixelRect(x: 150, y: 120, width: 150, height: 80))
    }

    @Test func clickingToSelectDoesNotMove() throws {
        let editor = makeEditor(fixture)
        editor.press("n")
        editor.click(PixelPoint(x: 300, y: 300))
        let before = editor.marks
        editor.press("v")
        editor.click(PixelPoint(x: 302, y: 301))
        #expect(editor.selectedID == before.first?.id)
        #expect(editor.marks == before)
    }

    @Test func movingDetachesAMarkFromItsTarget() throws {
        let editor = makeEditor(fixture)
        editor.press("c")
        editor.click(fixture.point(in: fixture["update"]))
        editor.press("v")
        let center = fixture.point(in: fixture["update"])
        editor.drag(from: center, to: PixelPoint(x: center.x - 200, y: center.y))
        #expect(editor.marks.only?.targetID == nil)
    }
}

extension Array {
    /// The one element, or nil when there are none or several.
    var only: Element? { count == 1 ? first : nil }
}
