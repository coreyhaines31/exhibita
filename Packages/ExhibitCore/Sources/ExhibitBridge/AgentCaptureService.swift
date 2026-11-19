import CoreGraphics
import ExhibitCore
import ExhibitShell
import ExhibitStore
import ExhibitTargets
import Foundation

/// A still image from the screen, already filtered by the policy: never-capture windows refused, left out and
/// blacked out. The app's ScreenCaptureKit code implements it; tests pass a fake.
public protocol CaptureProvider: Sendable {
    /// Throws a `BridgeError` for permission, a window not found or ambiguous, a never-capture window or a
    /// missing display. Never prompts for permission, never activates anything and never moves focus.
    func capture(_ target: CaptureTarget, policy: CapturePolicy) async throws -> ProvidedCapture
}

public struct ProvidedCapture: @unchecked Sendable {
    public var image: CGImage
    public var scale: Double
    public var appName: String?
    public var windowTitle: String?
    /// One reason per never-capture window drawn black.
    public var blackedOut: [String]

    public init(image: CGImage, scale: Double, appName: String? = nil, windowTitle: String? = nil,
                blackedOut: [String] = []) {
        self.image = image
        self.scale = scale
        self.appName = appName
        self.windowTitle = windowTitle
        self.blackedOut = blackedOut
    }
}

/// Answers bridge requests. A capture is saved to history tagged as an agent's, its targets are found, detected
/// secrets are blurred in the copy the agent gets (unless the policy turns that off), and the person is told.
/// The original in the bundle is never changed.
public struct AgentCaptureService: Sendable {
    public typealias FindTargets = @Sendable (CGImage) async throws -> [Target]

    let store: CaptureStore
    let provider: any CaptureProvider
    let policy: @Sendable () -> CapturePolicy
    let findTargets: FindTargets
    let present: @Sendable (UUID) async -> Bool
    let didCapture: @Sendable (UUID) async -> Void

    /// - Parameters:
    ///   - policy: read on every request, so a change in Settings applies to the next capture.
    ///   - present: shows a capture to the person (`exhibit open`); returns false when it could not.
    ///   - didCapture: called after an agent capture is saved, to flash the menu bar glyph and refresh history.
    public init(store: CaptureStore, provider: any CaptureProvider, policy: @escaping @Sendable () -> CapturePolicy,
                findTargets: @escaping FindTargets = { try await TargetFinder().findTargets(in: $0) },
                present: @escaping @Sendable (UUID) async -> Bool,
                didCapture: @escaping @Sendable (UUID) async -> Void = { _ in }) {
        self.store = store
        self.provider = provider
        self.policy = policy
        self.findTargets = findTargets
        self.present = present
        self.didCapture = didCapture
    }

    public func handle(_ request: BridgeRequest) async -> BridgeResponse {
        do {
            switch BridgeRequest.Method(rawValue: request.method) {
            case .ping:
                return BridgeResponse(id: request.id, pong: true)
            case .capture:
                return BridgeResponse(id: request.id, capture: try await capture(request.capture ?? .init()))
            case .open:
                guard let parameters = request.open else {
                    throw BridgeError(.badRequest, "open needs a capture id.")
                }
                return BridgeResponse(id: request.id, open: try await open(parameters.captureID))
            case nil:
                throw BridgeError(.unknownMethod, "Unknown request \"\(request.method)\". This Exhibit A knows "
                                  + "ping, capture and open.")
            }
        } catch let error as BridgeError {
            return BridgeResponse(id: request.id, error: error)
        } catch {
            return BridgeResponse(id: request.id, error: BridgeError(.captureFailed, "\(error)"))
        }
    }

    func capture(_ parameters: CaptureParameters) async throws -> CaptureResult {
        let target = try parameters.target()
        let policy = policy()
        let provided = try await provider.capture(target, policy: policy)
        let id = UUID()
        do {
            try store.create(image: provided.image, scale: provided.scale, capturedBy: .agent,
                             appName: provided.appName, windowTitle: provided.windowTitle, id: id)
        } catch {
            throw BridgeError(.captureFailed, "The capture could not be saved to history: \(error)")
        }
        let targets: [Target]
        do {
            targets = try await findTargets(provided.image)
        } catch {
            // Without targets nothing can be blurred, so the agent gets nothing; the person still has it.
            await didCapture(id)
            throw BridgeError(.captureFailed, "Reading text in the capture failed, so secrets could not be "
                              + "blurred. The capture is in history for the person: \(error)")
        }
        var document = try store.load(id).document
        document.targets = targets
        let blurs = policy.agentAutoBlur ? Self.autoBlurMarks(targets, kinds: policy.autoBlurKinds) : []
        // The blurs are marks on the document, so every later render of the capture (by the CLI or the editor)
        // keeps them, and the person can still remove them; original.png is untouched.
        document.marks += blurs
        let image = store.exportURL(for: id)
        do {
            try store.save(document)
            let original = try store.load(id).original
            try PNG.encode(Renderer.render(document, original: original)).write(to: image, options: .atomic)
        } catch {
            await didCapture(id)
            throw BridgeError(.captureFailed, "The capture could not be written: \(error)")
        }
        await didCapture(id)
        var kinds: [String: Int] = [:]
        for target in targets where blurs.contains(where: { $0.targetID == target.id }) {
            kinds[target.kind.rawValue, default: 0] += 1
        }
        return CaptureResult(id: id, bundle: store.url(for: id).path, image: image.path,
                             width: provided.image.width, height: provided.image.height, scale: provided.scale,
                             appName: provided.appName, windowTitle: provided.windowTitle,
                             autoBlur: .init(enabled: policy.agentAutoBlur, blurred: blurs.count, kinds: kinds),
                             blackedOut: provided.blackedOut, targets: targets.count)
    }

    /// One blur per target of the auto-blur kinds.
    public static func autoBlurMarks(_ targets: [Target], kinds: [TargetKind]) -> [Mark] {
        targets.filter { kinds.contains($0.kind) }.map { Mark.blur($0.rect, targetID: $0.id) }
    }

    func open(_ id: UUID) async throws -> OpenResult {
        guard FileManager.default.fileExists(atPath: store.url(for: id).path) else {
            throw BridgeError(.unknownCapture, "No capture with id \(id.uuidString) in history.")
        }
        return OpenResult(id: id, shown: await present(id))
    }
}
