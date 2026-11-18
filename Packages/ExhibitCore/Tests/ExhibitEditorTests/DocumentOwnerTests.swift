import ExhibitCore
@testable import ExhibitEditor
import ExhibitStore
import Foundation
import Testing

@MainActor
@Suite struct DocumentOwnerTests {
    let fixture = EditorFixture()

    @Test func changesAreCoalescedAndWrittenWithinTheDelay() async throws {
        let sink = RecordingSink()
        let editor = makeEditor(fixture, sink: sink, delay: 0.05)
        editor.press("n")
        for index in 0..<5 {
            editor.click(PixelPoint(x: 100 + Double(index) * 60, y: 100))
        }
        #expect(sink.documents.isEmpty, "nothing written before the delay")
        try await Task.sleep(for: .milliseconds(300))
        #expect(sink.documents.count == 1, "five changes, one write")
        #expect(sink.documents.last?.marks.count == 5)
    }

    @Test func flushWritesAtOnce() {
        let sink = RecordingSink()
        let editor = makeEditor(fixture, sink: sink, delay: 10)
        editor.press("n")
        editor.click(PixelPoint(x: 100, y: 100))
        editor.owner.flush()
        #expect(sink.documents.last?.marks.count == 1)
    }

    /// The race from issue 8: a target result arriving after marks were added must not overwrite them, and marks
    /// added after targets arrive must not drop the targets.
    @Test func targetsMergeIntoTheOpenDocumentWithoutLosingMarks() async throws {
        let store = temporaryStore()
        defer { removeStore(store) }
        let bare = EditorFixture(withTargets: false)
        try store.prepare()
        try CaptureBundle.save(bare.document, original: bare.fixture.image, in: store.directory)

        let captures = OpenCaptures(store: store, writer: DocumentWriter(sink: store, delay: 0.02))
        captures.beginFinding(bare.document.id)
        let open = try await captures.open(bare.document.id)
        let editor = CaptureEditor(owner: open.owner)
        #expect(!editor.targetsLoaded)

        editor.press("r")
        editor.drag(from: PixelPoint(x: 10, y: 10), to: PixelPoint(x: 100, y: 100))
        try await Task.sleep(for: .milliseconds(100))
        #expect(try store.load(bare.document.id).document.marks.count == 1)

        captures.targetsFound(fixture.document.targets, for: bare.document.id)
        editor.press("n")
        editor.click(PixelPoint(x: 300, y: 300))
        captures.close(bare.document.id)

        let saved = try store.load(bare.document.id).document
        #expect(saved.marks.map(\.kind) == [.box, .step])
        #expect(saved.targets == fixture.document.targets)
    }

    @Test func targetsForAClosedCaptureAreWrittenBeforeItReopens() async throws {
        let store = temporaryStore()
        defer { removeStore(store) }
        let bare = EditorFixture(withTargets: false)
        var marked = bare.document
        marked.marks = [.box(PixelRect(x: 1, y: 1, width: 20, height: 20))]
        try store.prepare()
        try CaptureBundle.save(marked, original: bare.fixture.image, in: store.directory)

        let captures = OpenCaptures(store: store)
        captures.beginFinding(marked.id)
        captures.targetsFound(fixture.document.targets, for: marked.id)
        // Opening straight after: the load is queued behind the target write.
        let open = try await captures.open(marked.id)
        #expect(open.owner.targetsLoaded)
        #expect(open.owner.document.targets == fixture.document.targets)
        #expect(open.owner.document.marks == marked.marks)
    }

    @Test func targetsArrivingWhileACaptureOpensAreHeldAndMerged() async throws {
        let store = temporaryStore()
        defer { removeStore(store) }
        let bare = EditorFixture(withTargets: false)
        try store.prepare()
        try CaptureBundle.save(bare.document, original: bare.fixture.image, in: store.directory)

        let writer = DocumentWriter(sink: store, delay: 0.02)
        let captures = OpenCaptures(store: store, writer: writer)
        captures.beginFinding(bare.document.id)
        // Hold the writer's queue so the open is still loading when the result arrives.
        let gate = DispatchSemaphore(value: 0)
        writer.enqueue { gate.wait() }
        async let opened = captures.open(bare.document.id)
        for _ in 0..<1000 where !captures.isOpening(bare.document.id) {
            await Task.yield()
        }
        #expect(captures.isOpening(bare.document.id))
        captures.targetsFound(fixture.document.targets, for: bare.document.id)
        gate.signal()
        let open = try await opened
        #expect(open.owner.targetsLoaded)
        #expect(open.owner.document.targets == fixture.document.targets)
        captures.close(bare.document.id)
        #expect(try store.load(bare.document.id).document.targets == fixture.document.targets)
    }

    @Test func aFailedFinderStopsTheWait() {
        let store = temporaryStore()
        let captures = OpenCaptures(store: store)
        let bare = EditorFixture(withTargets: false)
        captures.beginFinding(bare.document.id)
        let open = captures.open(document: bare.document, original: bare.fixture.image)
        #expect(!open.owner.targetsLoaded)
        captures.findingFailed(bare.document.id)
        #expect(open.owner.targetsLoaded)
        #expect(!captures.isFinding(bare.document.id))
    }

    @Test func openingTwiceGivesTheSameOwner() {
        let captures = OpenCaptures(store: temporaryStore())
        let first = captures.open(document: fixture.document, original: fixture.fixture.image)
        let second = captures.open(document: fixture.document, original: fixture.fixture.image)
        #expect(first.owner === second.owner)
        #expect(captures.openIDs == [fixture.document.id])
    }

    /// Marks survive a force quit: nothing is flushed, the process just stops after the save delay.
    @Test func marksReachDiskWithoutAFlush() async throws {
        let store = temporaryStore()
        defer { removeStore(store) }
        try store.prepare()
        try CaptureBundle.save(fixture.document, original: fixture.fixture.image, in: store.directory)
        let captures = OpenCaptures(store: store)
        let editor = CaptureEditor(owner: try await captures.open(fixture.document.id).owner)
        editor.press("b")
        editor.click(fixture.point(in: fixture["email"]))
        try await Task.sleep(for: .milliseconds(400))
        let saved = try store.load(fixture.document.id).document
        #expect(saved.marks == editor.marks)
    }
}
