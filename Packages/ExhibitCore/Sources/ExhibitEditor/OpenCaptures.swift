import CoreGraphics
import ExhibitCore
import ExhibitStore
import Foundation

/// A capture open in the editor: its document's owner and the original image.
@MainActor
public struct OpenCapture {
    public let owner: DocumentOwner
    public let original: CGImage
}

/// Routes every document write for captures the editor may have open. Background target results go to the
/// open capture's owner when there is one, are held while a capture is being opened, and are otherwise written
/// to the store on the writer's queue, ordered before any later open of the same capture. This closes the race
/// where a target save loaded the document, the editor saved marks, and the target save then wrote over them.
@MainActor
public final class OpenCaptures {
    public let store: CaptureStore
    public let writer: DocumentWriter
    private var captures: [UUID: OpenCapture] = [:]
    private var loading: Set<UUID> = []
    private var finding: Set<UUID> = []
    /// Target results that arrived while their capture was loading. nil means the finder failed.
    private var heldResults: [UUID: [Target]?] = [:]
    /// Auto-blur marks of agent captures that arrived while their capture was loading.
    private var heldMarks: [UUID: [Mark]] = [:]

    public init(store: CaptureStore, writer: DocumentWriter? = nil) {
        self.store = store
        self.writer = writer ?? DocumentWriter(sink: store)
    }

    public func capture(_ id: UUID) -> OpenCapture? {
        captures[id]
    }

    public var openIDs: [UUID] { Array(captures.keys) }

    /// Whether `id` is being loaded to open.
    public func isOpening(_ id: UUID) -> Bool {
        loading.contains(id)
    }

    // MARK: - Targets

    /// The finder has started on `id`. Until it reports, an editor on `id` shows "reading text".
    public func beginFinding(_ id: UUID) {
        finding.insert(id)
    }

    public func isFinding(_ id: UUID) -> Bool {
        finding.contains(id)
    }

    /// The finder's result for `id`, delivered on the main actor.
    public func targetsFound(_ targets: [Target], for id: UUID) {
        finding.remove(id)
        if let capture = captures[id] {
            capture.owner.mergeTargets(targets)
        } else if loading.contains(id) {
            heldResults[id] = .some(targets)
        } else {
            let store = store
            writer.enqueue { try? store.updateTargets(targets, for: id) }
        }
    }

    /// An agent capture's targets and auto-blur marks. An open capture's owner merges both; while the capture
    /// is loading they are held; otherwise they are written on the writer's queue, ahead of any later open, and
    /// this returns once they are on disk. Either way no editor can save the capture without the blurs.
    public func agentTargetsFound(_ targets: [Target], blurs: [Mark], for id: UUID) async throws {
        finding.remove(id)
        if let capture = captures[id] {
            capture.owner.mergeTargets(targets)
            capture.owner.addMarks(blurs)
        } else if loading.contains(id) {
            heldResults[id] = .some(targets)
            heldMarks[id, default: []] += blurs
        } else {
            let store = store
            try await writer.perform { try store.updateTargets(targets, adding: blurs, for: id) }
        }
    }

    /// The finder failed on `id`. An open editor stops waiting for text.
    public func findingFailed(_ id: UUID) {
        finding.remove(id)
        if let capture = captures[id] {
            capture.owner.targetsUnavailable()
        } else if loading.contains(id) {
            heldResults[id] = .some(nil)
        }
    }

    // MARK: - Opening and closing

    /// Opens a capture already in memory, such as one just taken.
    @discardableResult
    public func open(document: CaptureDocument, original: CGImage) -> OpenCapture {
        if let existing = captures[document.id] { return existing }
        let owner = DocumentOwner(document: document, targetsLoaded: !finding.contains(document.id), writer: writer)
        let capture = OpenCapture(owner: owner, original: original)
        captures[document.id] = capture
        return capture
    }

    /// Opens a capture from history. The load runs on the writer's queue, after any target write queued for it.
    public func open(_ id: UUID) async throws -> OpenCapture {
        if let existing = captures[id] { return existing }
        loading.insert(id)
        defer { loading.remove(id) }
        let store = store
        let loaded = try await writer.perform { try LoadedCapture(store.load(id)) }
        if let existing = captures[id] { return existing }
        let capture = open(document: loaded.document, original: loaded.original)
        if let held = heldResults.removeValue(forKey: id) {
            if let targets = held {
                capture.owner.mergeTargets(targets)
            } else {
                capture.owner.targetsUnavailable()
            }
        }
        if let marks = heldMarks.removeValue(forKey: id) { capture.owner.addMarks(marks) }
        return capture
    }

    /// Writes any pending change and forgets the capture. Later target results go straight to the store.
    public func close(_ id: UUID) {
        guard let capture = captures.removeValue(forKey: id) else { return }
        capture.owner.flush()
    }

    /// Deletes a capture for good, open or not (issue 109's copy and delete). The capture is forgotten without a
    /// flush, and the delete runs on the writer's queue after anything already queued, so no pending or late write
    /// can recreate the bundle: a write after the delete finds no `original.png` and fails, and later target
    /// results for the id fail to load and are dropped.
    public func delete(_ id: UUID) async throws {
        captures.removeValue(forKey: id)
        heldResults[id] = nil
        heldMarks[id] = nil
        let store = store
        try await writer.perform { try store.delete(id) }
    }

    /// Writes every open capture's pending changes, for quitting.
    public func flushAll() {
        writer.flush()
    }
}

/// `CaptureBundle.Loaded` handed across the writer's queue.
private struct LoadedCapture: @unchecked Sendable {
    let document: CaptureDocument
    let original: CGImage

    init(_ loaded: CaptureBundle.Loaded) {
        document = loaded.document
        original = loaded.original
    }
}
