import ExhibitBridge
import ExhibitCore
import ExhibitEditor
import ExhibitShell
import ExhibitStore
import Foundation
import os

/// Serves the capture bridge for the life of the app: `exhibit capture` and `exhibit open` reach it over
/// `~/Library/Application Support/Exhibit A/Bridge/bridge.sock` (`docs/product/capture-bridge.md`).
@MainActor
final class BridgeHost {
    private nonisolated static let logger = Logger(subsystem: Brand.bundleIdentifier, category: "Bridge")

    private let server: BridgeServer

    /// - Parameters:
    ///   - present: shows a capture to the person for `exhibit open`. The one call site to change when the way
    ///     a capture is handed over changes.
    ///   - captures: the editor's open captures. An agent capture's targets and auto-blur go through it, so a
    ///     person who opens the capture before its text is read never saves over the blurs.
    ///   - didCapture: after an agent capture is saved: flash the glyph, refresh history.
    init(store: CaptureStore, supportDirectory: URL, policy: PolicySnapshot, captures: OpenCaptures,
         present: @escaping @MainActor (UUID) -> Bool, didCapture: @escaping @MainActor (UUID) async -> Void) {
        let service = AgentCaptureService(
            store: store, provider: ScreenCaptureProvider(), policy: { policy.current },
            documents: EditorDocumentSink(captures: captures),
            present: { id in await MainActor.run { present(id) } },
            didCapture: { id in await didCapture(id) })
        server = BridgeServer(socketURL: BridgeSocket.url(inSupportDirectory: supportDirectory)) { request in
            await service.handle(request)
        }
    }

    func start() {
        do {
            try server.start()
        } catch {
            // The app works without the bridge; only agents' live captures are unavailable.
            Self.logger.error("The capture bridge could not start: \(String(describing: error))")
        }
    }

    func stop() {
        server.stop()
    }
}

/// An agent capture's document writes, through the editor's `OpenCaptures` on the main actor.
struct EditorDocumentSink: AgentDocumentSink {
    let captures: OpenCaptures

    func beginFinding(_ id: UUID) async {
        await captures.beginFinding(id)
    }

    func findingFailed(_ id: UUID) async {
        await captures.findingFailed(id)
    }

    func targetsFound(_ targets: [Target], adding marks: [Mark], for id: UUID) async throws {
        try await captures.agentTargetsFound(targets, blurs: marks, for: id)
    }
}
