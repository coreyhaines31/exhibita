import AppKit
import ExhibitCore
import ExhibitEditor
import ExhibitShell
import ExhibitStore
import ExhibitTargets
import os

/// From a hotkey to a saved capture: permission check, a still of every display, the overlay over it, history,
/// the clipboard, and targets found in the background.
@MainActor
final class CaptureController {
    private nonisolated static let logger = Logger(subsystem: Brand.bundleIdentifier, category: "Capture")

    private let model: AppModel
    private let editors: EditorWindows
    let overlay = SelectionOverlay()
    /// Confirms a capture that went straight to the clipboard, which opens no window.
    let copiedNote = CopiedNote()
    /// The never-capture list and auto-blur, read fresh for every capture.
    var policy: () -> CapturePolicy = { CapturePolicy() }
    /// Opens the panel: to explain the permission, or why a window pick was refused.
    var showPanel: () -> Void = {}
    /// Closes the panel once a capture is taken. Until then it stays as it was.
    var closePanel: () -> Void = {}
    /// Keeps the panel open while the overlay is up: a click on the overlay would close a transient popover.
    var holdPanel: (Bool) -> Void = { _ in }
    /// Runs once the overlay is done, to refresh what the panel shows now that nothing is frozen.
    var didFinish: () -> Void = {}
    private var isFreezing = false
    /// How long the last freeze took, from the hotkey to every display's still, for the end-to-end timings.
    private(set) var lastFreeze: Duration?

    init(model: AppModel, editors: EditorWindows) {
        self.model = model
        self.editors = editors
    }

    /// The hotkey. Before any window of Exhibit A's appears, closes or changes, every display is frozen as a
    /// still; the overlay shows the stills and the capture is cut out of them, so it is exactly what was on
    /// screen when the key was pressed.
    func start(_ action: HotkeyAction) {
        guard !overlay.isActive, !isFreezing else { return }
        // Read without touching the model: a model change would redraw the panel before the freeze.
        let permission = ScreenRecording.state
        guard permission == .granted else {
            model.clearCaptureRefusal()
            model.permission = permission
            showPanel()
            return
        }
        let screens = NSScreen.screens
        let displays = screens.compactMap { screen in
            screen.displayID.map { DisplayGeometry(id: $0, frame: screen.frame, scale: screen.backingScaleFactor) }
        }
        let mainDisplayHeight = screens.first?.frame.height ?? 0
        let windows = WindowList.onScreen()
        let policy = policy()
        let started = ContinuousClock.now
        isFreezing = true
        Task {
            let frozen: FrozenScreen
            do {
                frozen = try await ScreenCapturer.freeze(displays, windows: windows,
                                                         mainDisplayHeight: mainDisplayHeight, policy: policy)
            } catch {
                isFreezing = false
                Self.logger.error("Freezing the screen failed: \(error.localizedDescription)")
                NSSound.beep()
                didFinish()
                return
            }
            isFreezing = false
            lastFreeze = ContinuousClock.now - started
            holdPanel(true)
            overlay.begin(frozen) { [weak self] outcome in
                guard let self else { return }
                holdPanel(false)
                Task { await self.finish(outcome, frozen: frozen, action: action) }
            }
        }
    }

    private func finish(_ outcome: SelectionOverlay.Outcome, frozen: FrozenScreen, action: HotkeyAction) async {
        defer { didFinish() }
        let captured: CapturedImage
        do {
            switch outcome {
            case .cancelled:
                // Everything stays as it was, the panel included.
                return
            case .region(let region):
                captured = try ScreenCapturer.cut(region, from: frozen)
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
                // The window's own frame cut out of the still: what was visible of it at the hotkey.
                guard let region = SelectionGeometry.region(forWindow: window.frame, in: frozen.displays,
                                                            mainDisplayHeight: frozen.mainDisplayHeight) else {
                    throw CaptureFailure.windowGone
                }
                captured = try ScreenCapturer.cut(region, from: frozen, appName: window.ownerName,
                                                  windowTitle: window.title)
            }
        } catch {
            Self.logger.error("Capture failed: \(error.localizedDescription)")
            NSSound.beep()
            return
        }
        model.clearCaptureRefusal()
        closePanel()
        await save(captured, action: action)
    }

    func save(_ captured: CapturedImage, action: HotkeyAction) async {
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
            if copyToClipboard(captured.image) {
                copiedNote.show(on: Self.screen(for: captured.displayID))
                Self.logger.info("Captured to the clipboard")
            } else {
                Self.logger.error("Copying the capture failed")
                NSSound.beep()
            }
        case .captureAndEdit:
            // The same document `create` wrote, so the editor opens without reading it back.
            let document = CaptureDocument(id: id, createdAt: item.createdAt, size: item.size, scale: captured.scale,
                                           source: CaptureSource(appName: captured.appName,
                                                                 windowTitle: captured.windowTitle,
                                                                 capturedBy: .person))
            editors.open(document: document, original: captured.image, on: Self.screen(for: captured.displayID))
            Self.logger.info("Captured and opened the editor")
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

    /// False when the image could not be encoded or the clipboard refused it.
    @discardableResult
    func copyToClipboard(_ image: CGImage) -> Bool {
        guard let png = try? PNG.encode(image) else { return false }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setData(png, forType: .png)
    }

    func copyCapture(_ id: UUID) {
        let store = model.store
        Task {
            let image = await Task.detached { try? store.load(id).original }.value
            if let image { copyToClipboard(image) }
        }
    }
}
