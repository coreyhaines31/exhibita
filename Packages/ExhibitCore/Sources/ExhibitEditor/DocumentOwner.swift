import ExhibitCore
import Foundation
import Observation

/// The single owner of an open capture's document. Every change (marks from the editor, targets from the
/// background finder) goes through it into the one in-memory document, which is then written whole. Nothing
/// else writes an open capture's `document.json`, so a late target result can never overwrite marks.
@MainActor
@Observable
public final class DocumentOwner {
    public private(set) var document: CaptureDocument
    /// False while the background finder is still reading the capture's text.
    public private(set) var targetsLoaded: Bool
    @ObservationIgnored private let writer: DocumentWriter

    public init(document: CaptureDocument, targetsLoaded: Bool, writer: DocumentWriter) {
        self.document = document
        self.targetsLoaded = targetsLoaded
        self.writer = writer
    }

    public var id: UUID { document.id }

    /// Replaces the marks and queues a write.
    public func setMarks(_ marks: [Mark]) {
        guard marks != document.marks else { return }
        document.marks = marks
        writer.submit(document)
    }

    /// Stores targets found in the background. Marks are untouched.
    public func mergeTargets(_ targets: [Target]) {
        document.targets = targets
        targetsLoaded = true
        writer.submit(document)
    }

    /// Called after `addMarks`, so an editor can keep the added marks in its undo history.
    @ObservationIgnored public var onMarksAdded: (([Mark]) -> Void)?

    /// Adds marks made outside the editor (an agent capture's auto-blur) to the person's marks and queues a write.
    public func addMarks(_ marks: [Mark]) {
        let added = marks.filter { mark in !document.marks.contains { $0.id == mark.id } }
        guard !added.isEmpty else { return }
        document.marks += added
        writer.submit(document)
        onMarksAdded?(added)
    }

    /// The finder failed: stop waiting for targets. Nothing to write.
    public func targetsUnavailable() {
        targetsLoaded = true
    }

    /// Writes any pending change now. Call when the editor closes.
    public func flush() {
        writer.flush()
    }
}
