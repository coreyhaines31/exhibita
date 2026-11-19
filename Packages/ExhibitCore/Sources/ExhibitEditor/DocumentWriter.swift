import ExhibitCore
import ExhibitStore
import Foundation

/// Where documents are written. `CaptureStore` in the app; a recorder in tests.
public protocol DocumentSaving: Sendable {
    func save(_ document: CaptureDocument) throws
}

extension CaptureStore: DocumentSaving {}

/// Writes documents on one serial queue. A changed document is written at most `delay` after the change, with
/// changes in between coalesced into one write of the latest version; `flush` writes what is pending at once.
///
/// Everything else that touches a capture's files from the editor side (loading it to open, storing targets
/// for a capture nobody has open) runs on the same queue, so those steps happen in the order they were asked for.
public final class DocumentWriter: @unchecked Sendable {
    public let delay: TimeInterval
    private let sink: DocumentSaving
    private let queue = DispatchQueue(label: "com.exhibitaformac.ExhibitA.documents", qos: .userInitiated)
    private let lock = NSLock()
    /// Guarded by `lock`.
    private var pending: [UUID: CaptureDocument] = [:]
    private var scheduled = false
    /// Called on the writer's queue when a write fails. The document stays in memory, and the next change
    /// writes it again.
    public var onError: @Sendable (Error) -> Void = { _ in }

    public init(sink: DocumentSaving, delay: TimeInterval = 0.1) {
        self.sink = sink
        self.delay = delay
    }

    /// Queues `document` to be written; replaces any version of it still waiting.
    public func submit(_ document: CaptureDocument) {
        lock.lock()
        pending[document.id] = document
        let needsSchedule = !scheduled
        scheduled = true
        lock.unlock()
        guard needsSchedule else { return }
        queue.asyncAfter(deadline: .now() + delay) { [self] in writePending() }
    }

    /// Writes every pending document now and waits for the writes to finish.
    public func flush() {
        queue.sync { writePending() }
    }

    /// Runs `work` on the writer's queue after everything queued before it, writing pending documents first.
    public func perform<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                writePending()
                continuation.resume(with: Result { try work() })
            }
        }
    }

    /// Like `perform`, without waiting.
    public func enqueue(_ work: @escaping @Sendable () -> Void) {
        queue.async { [self] in
            writePending()
            work()
        }
    }

    /// Runs on `queue` only.
    private func writePending() {
        lock.lock()
        let documents = pending.values.sorted { $0.id.uuidString < $1.id.uuidString }
        pending = [:]
        scheduled = false
        lock.unlock()
        for document in documents {
            do {
                try sink.save(document)
            } catch {
                onError(error)
            }
        }
    }
}
