import AppKit
import ExhibitCore
import ExhibitShell
import ExhibitStore
import ExhibitTargets
import os

/// From a hotkey to a saved capture: permission check, overlay, ScreenCaptureKit, history, the clipboard, and
/// targets found in the background.
@MainActor
final class CaptureController {
    private nonisolated static let logger = Logger(subsystem: Brand.bundleIdentifier, category: "Capture")

    private let model: AppModel
    private let overlay = SelectionOverlay()
    private let policy = CapturePolicy()
    /// Opens the panel: to explain the permission, or with a new capture selected.
    var showPanel: () -> Void = {}

    init(model: AppModel) {
        self.model = model
    }

    func start(_ action: HotkeyAction) {
        guard !overlay.isActive else { return }
        model.permission = ScreenRecording.state
        guard model.permission == .granted else {
            showPanel()
            return
        }
        overlay.begin { [weak self] outcome in
            guard let self else { return }
            Task { await self.finish(outcome, action: action) }
        }
    }

    private func finish(_ outcome: SelectionOverlay.Outcome, action: HotkeyAction) async {
        let captured: CapturedImage
        do {
            switch outcome {
            case .cancelled:
                return
            case .region(let region):
                captured = try await ScreenCapturer.capture(region)
            case .window(let window):
                // The never-capture list (unit 6) decides here; everything is allowed for now.
                guard policy.decision(for: CaptureSubject(appName: window.ownerName)) == .allow else { return }
                captured = try await ScreenCapturer.capture(windowID: window.id)
            }
        } catch {
            Self.logger.error("Capture failed: \(error.localizedDescription)")
            NSSound.beep()
            return
        }
        await save(captured, action: action)
    }

    private func save(_ captured: CapturedImage, action: HotkeyAction) async {
        let store = model.store
        let id = UUID()
        do {
            _ = try await Task.detached(priority: .userInitiated) {
                try store.create(image: captured.image, scale: captured.scale, capturedBy: .person,
                                 appName: captured.appName, windowTitle: captured.windowTitle, id: id)
            }.value
        } catch {
            Self.logger.error("Saving the capture failed: \(error.localizedDescription)")
            NSSound.beep()
            return
        }
        switch action {
        case .captureToClipboard:
            copyToClipboard(captured.image)
            await model.reload()
        case .captureAndEdit:
            // The editor is unit 5. Until then the panel opens with the new capture selected.
            model.selected = id
            await model.reload()
            showPanel()
        }
        findTargets(in: captured, id: id)
    }

    /// OCR and detectors run in the background and are saved into the bundle when done.
    private func findTargets(in captured: CapturedImage, id: UUID) {
        let store = model.store
        Task.detached(priority: .utility) {
            do {
                let targets = try await TargetFinder().findTargets(in: captured.image)
                try store.updateTargets(targets, for: id)
            } catch {
                Self.logger.error("Finding targets failed: \(error.localizedDescription)")
            }
        }
    }

    func copyToClipboard(_ image: CGImage) {
        guard let png = try? PNG.encode(image) else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(png, forType: .png)
    }

    func copyCapture(_ id: UUID) {
        let store = model.store
        Task {
            let image = await Task.detached { try? store.load(id).original }.value
            if let image { copyToClipboard(image) }
        }
    }
}
