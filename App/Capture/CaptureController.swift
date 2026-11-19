import AppKit
import ExhibitCore
import ExhibitEditor
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
    private let editors: EditorWindows
    private let overlay = SelectionOverlay()
    /// The never-capture list and auto-blur, read fresh for every capture.
    var policy: () -> CapturePolicy = { CapturePolicy() }
    /// Opens the panel: to explain the permission, or with a new capture selected.
    var showPanel: () -> Void = {}

    init(model: AppModel, editors: EditorWindows) {
        self.model = model
        self.editors = editors
    }

    func start(_ action: HotkeyAction) {
        guard !overlay.isActive else { return }
        model.clearCaptureRefusal()
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
                captured = try await ScreenCapturer.capture(region, policy: policy())
            case .window(let window):
                let bundle = NSRunningApplication(processIdentifier: window.ownerPID)?.bundleIdentifier
                let subject = CaptureSubject(bundleIdentifier: bundle, appName: window.ownerName)
                if case .blackOut(let reason) = policy().decision(for: subject) {
                    // The never-capture list refuses the window. The overlay has closed; the panel says why.
                    NSSound.beep()
                    model.refuseCapture(reason: reason)
                    showPanel()
                    return
                }
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
        let item: HistoryItem
        do {
            item = try await Task.detached(priority: .userInitiated) {
                try store.create(image: captured.image, scale: captured.scale, capturedBy: .person,
                                 appName: captured.appName, windowTitle: captured.windowTitle, id: id)
            }.value
        } catch {
            Self.logger.error("Saving the capture failed: \(error.localizedDescription)")
            NSSound.beep()
            return
        }
        // Before the editor opens, so it shows "reading text" until the result arrives.
        editors.captures.beginFinding(id)
        switch action {
        case .captureToClipboard:
            copyToClipboard(captured.image)
        case .captureAndEdit:
            // The same document `create` wrote, so the editor opens without reading it back.
            let document = CaptureDocument(id: id, createdAt: item.createdAt, size: item.size, scale: captured.scale,
                                           source: CaptureSource(appName: captured.appName,
                                                                 windowTitle: captured.windowTitle,
                                                                 capturedBy: .person))
            editors.open(document: document, original: captured.image, on: Self.screen(for: captured.displayID))
        }
        findTargets(in: captured, id: id)
        await model.reload()
    }

    private static func screen(for displayID: CGDirectDisplayID?) -> NSScreen? {
        guard let displayID else { return NSScreen.main }
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return NSScreen.screens.first { ($0.deviceDescription[key] as? NSNumber)?.uint32Value == displayID }
            ?? NSScreen.main
    }

    /// OCR and detectors run in the background. The result goes through `OpenCaptures`, which merges it into
    /// an open editor's document or writes it to the bundle, so it never overwrites marks.
    private func findTargets(in captured: CapturedImage, id: UUID) {
        let captures = editors.captures
        Task.detached(priority: .utility) {
            do {
                let targets = try await TargetFinder().findTargets(in: captured.image)
                await MainActor.run { captures.targetsFound(targets, for: id) }
            } catch {
                Self.logger.error("Finding targets failed: \(error.localizedDescription)")
                await MainActor.run { captures.findingFailed(id) }
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
