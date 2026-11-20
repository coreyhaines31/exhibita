import ExhibitCore
@testable import ExhibitEditor
import ExhibitInterpret
import Foundation

/// Holds callers until it is opened. Opening before anyone waits lets them straight through.
final class Gate: @unchecked Sendable {
    private let lock = NSLock()
    private var isOpen = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    init(open: Bool = false) {
        isOpen = open
    }

    func wait() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if isOpen {
                lock.unlock()
                continuation.resume()
            } else {
                waiting.append(continuation)
                lock.unlock()
            }
        }
    }

    func open() {
        lock.lock()
        isOpen = true
        let resumed = waiting
        waiting.removeAll()
        lock.unlock()
        resumed.forEach { $0.resume() }
    }
}

/// A transcriber that hears what the test says it heard. No microphone, no speech framework.
@MainActor
final class FakeTranscriber: SpeechTranscribing {
    var readiness: SpeechReadiness = .ready
    /// Held until opened, like a permission prompt waiting for an answer.
    var prepareGate = Gate(open: true)
    var downloadGate = Gate(open: true)
    var final = ""
    private(set) var prepareCalls = 0
    private(set) var startCalls = 0
    private(set) var finishCalls = 0
    private(set) var cancelCalls = 0
    private(set) var downloaded = false
    private var partial: (@MainActor (String) -> Void)?

    func prepare() async -> SpeechReadiness {
        prepareCalls += 1
        await prepareGate.wait()
        return readiness
    }

    func download(progress: @escaping @MainActor (Double) -> Void) async throws {
        progress(0.5)
        await downloadGate.wait()
        try Task.checkCancellation()
        progress(1)
        downloaded = true
        readiness = .ready
    }

    private(set) var hints: [String] = []

    func start(hints: [String], partial: @escaping @MainActor (String) -> Void) async throws {
        startCalls += 1
        self.hints = hints
        self.partial = partial
    }

    /// Words heard so far while D is held.
    func hear(_ text: String) {
        partial?(text)
    }

    func finish() async -> String {
        finishCalls += 1
        partial = nil
        return final
    }

    func cancel() {
        cancelCalls += 1
        partial = nil
    }
}

/// A model that answers with a fixed outcome, optionally only once its gate opens, and counts its calls.
class FakeModel: Interpreter, @unchecked Sendable {
    let outcome: Result<InterpretOutcome, ModelError>
    let gate: Gate
    private let lock = NSLock()
    private var count = 0

    init(_ outcome: Result<InterpretOutcome, ModelError>, gate: Gate = Gate(open: true)) {
        self.outcome = outcome
        self.gate = gate
    }

    var name: String { "fake-model" }

    var calls: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func interpret(_ request: InterpretRequest) async throws -> InterpretOutcome {
        lock.withLock { count += 1 }
        await gate.wait()
        return try outcome.get()
    }
}

/// A fake model that can also be warmed up, recording each screen it was asked to read ahead.
final class WarmingFakeModel: FakeModel, ScreenWarming, @unchecked Sendable {
    private let warmLock = NSLock()
    private var warmed: [[Target]] = []

    var warmUps: [[Target]] { warmLock.withLock { warmed } }

    func warmUp(_ targets: [Target]) {
        warmLock.withLock { warmed.append(targets) }
    }
}
