import ExhibitShell
import Foundation
import Observation
import os

/// The never-capture list and auto-blur switch, as Settings edits them. Saved to `policy.json` on every change.
/// Captures read `current` from any thread, so a change applies to the next capture, a person's or an agent's.
@MainActor
@Observable
final class CapturePolicyModel {
    private nonisolated static let logger = Logger(subsystem: Brand.bundleIdentifier, category: "Policy")

    private(set) var policy: CapturePolicy
    /// Why the file on disk was not used, when it could not be read; the defaults apply until the next change.
    private(set) var problem: String?
    @ObservationIgnored private let file: CapturePolicyFile?
    @ObservationIgnored nonisolated let snapshot: PolicySnapshot

    /// `file` nil keeps everything in memory, for renders.
    init(file: CapturePolicyFile?) {
        self.file = file
        let loaded = file?.load() ?? CapturePolicyFile.Loaded(policy: CapturePolicy())
        policy = loaded.policy
        problem = loaded.problem
        snapshot = PolicySnapshot(loaded.policy)
        if let problem = loaded.problem { Self.logger.error("\(problem)") }
    }

    func add(_ app: NeverCaptureApp) {
        var changed = policy
        changed.add(app)
        apply(changed)
    }

    func remove(_ app: NeverCaptureApp) {
        var changed = policy
        changed.remove(app)
        apply(changed)
    }

    func setAgentAutoBlur(_ enabled: Bool) {
        var changed = policy
        changed.agentAutoBlur = enabled
        apply(changed)
    }

    func restoreDefaults() {
        apply(CapturePolicy())
    }

    private func apply(_ changed: CapturePolicy) {
        guard changed != policy else { return }
        policy = changed
        snapshot.set(changed)
        do {
            try file?.save(changed)
            problem = nil
        } catch {
            problem = "Couldn't save the capture policy: \(error.localizedDescription)"
            Self.logger.error("Saving the policy failed: \(error.localizedDescription)")
        }
    }
}

/// The policy in effect, readable from the bridge's threads.
final class PolicySnapshot: @unchecked Sendable {
    private let lock = NSLock()
    private var value: CapturePolicy

    init(_ value: CapturePolicy) {
        self.value = value
    }

    var current: CapturePolicy { lock.withLock { value } }

    func set(_ policy: CapturePolicy) {
        lock.withLock { value = policy }
    }
}
