import Foundation

/// Copy and delete (issue 109): the capture is deleted only once the image is on the clipboard. Deleting is
/// permanent (there is no Recently Deleted), so a failed copy deletes nothing.
public enum CopyAndDelete {
    public enum Outcome: Equatable, Sendable {
        case copiedAndDeleted
        /// Nothing reached the clipboard; the capture is untouched.
        case copyFailed
        /// The image is on the clipboard but the capture could not be deleted.
        case deleteFailed
    }

    /// Copies, then deletes only if `copy` reported success.
    @MainActor
    public static func run(copy: () -> Bool, delete: () async throws -> Void) async -> Outcome {
        guard copy() else { return .copyFailed }
        do {
            try await delete()
            return .copiedAndDeleted
        } catch {
            return .deleteFailed
        }
    }

    /// What the note or status says afterwards.
    public static func message(for outcome: Outcome) -> String {
        switch outcome {
        case .copiedAndDeleted: "Copied and deleted"
        case .copyFailed: "Copying failed, nothing deleted"
        case .deleteFailed: "Copied, but deleting failed"
        }
    }
}
