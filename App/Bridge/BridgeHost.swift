import ExhibitBridge
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
    ///   - didCapture: after an agent capture is saved: flash the glyph, refresh history.
    init(store: CaptureStore, supportDirectory: URL, policy: PolicySnapshot,
         present: @escaping @MainActor (UUID) -> Bool, didCapture: @escaping @MainActor (UUID) async -> Void) {
        let service = AgentCaptureService(
            store: store, provider: ScreenCaptureProvider(), policy: { policy.current },
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
