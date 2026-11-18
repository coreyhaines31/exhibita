import AppKit
import ExhibitStore
import os
import PanelKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private nonisolated static let logger = Logger(subsystem: Brand.bundleIdentifier, category: "App")

    private var model: AppModel?
    private var statusItem: StatusItemController?
    private var settingsWindow: SettingsWindow?
    private var hotkeys: HotkeyCenter?
    private var capture: CaptureController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        PanelFont.register()
        LaunchAtLogin.applyDefault()

        let store = CaptureStore(directory: (try? CaptureStore.defaultDirectory())
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("Exhibit A Captures"))
        do {
            try store.prepare()
        } catch {
            Self.logger.error("Couldn't prepare the captures folder: \(error.localizedDescription)")
        }
        // Reading the permission never prompts. Nothing here asks for it.
        let model = AppModel(store: store, permission: ScreenRecording.state, system: SystemShortcuts.read(),
                             launchesAtLogin: LaunchAtLogin.isEnabled)
        model.onLaunchAtLoginChanged = { LaunchAtLogin.set($0) }
        self.model = model

        let capture = CaptureController(model: model)
        self.capture = capture
        let hotkeys = HotkeyCenter { [weak self] action in
            self?.refreshSystemState()
            self?.statusItem?.close()
            self?.capture?.start(action)
        }
        hotkeys.install(model.bindings)
        model.onBindingsChanged = { [weak hotkeys] in hotkeys?.apply($0) }
        self.hotkeys = hotkeys

        let actions = settingsActions(model: model, store: store)
        let settingsWindow = SettingsWindow(model: model, actions: actions) { [weak self] in
            self?.refreshSystemState()
        }
        self.settingsWindow = settingsWindow
        let statusItem = StatusItemController(model: model, actions: panelActions(model: model)) { [weak self] in
            self?.refreshSystemState()
            Task { await model.reload() }
        }
        self.statusItem = statusItem
        capture.showPanel = { [weak statusItem] in statusItem?.show() }

        Task { await model.reload() }
    }

    /// Permission and the system shortcuts can change in System Settings at any time. They are read again when
    /// the panel, Settings or a hotkey needs them, never on a timer.
    private func refreshSystemState() {
        guard let model else { return }
        model.permission = ScreenRecording.state
        model.updateSystemShortcuts(SystemShortcuts.read())
    }

    private func panelActions(model: AppModel) -> PanelActions {
        PanelActions(
            openSettings: { [weak self] in self?.settingsWindow?.show() },
            quit: { NSApp.terminate(nil) },
            allowScreenRecording: { ScreenRecording.request() },
            checkPermissionAgain: { [weak self] in self?.refreshSystemState() },
            openKeyboardSettings: { SystemShortcuts.openKeyboardSettings() },
            copy: { [weak self] in self?.capture?.copyCapture($0) },
            reveal: { id in NSWorkspace.shared.activateFileViewerSelecting([model.store.url(for: id)]) },
            delete: { id in Task { await model.delete(id) } }
        )
    }

    private func settingsActions(model: AppModel, store: CaptureStore) -> SettingsActions {
        SettingsActions(
            openKeyboardSettings: { SystemShortcuts.openKeyboardSettings() },
            openScreenRecordingSettings: { ScreenRecording.request() },
            checkPermissionAgain: { [weak self] in self?.refreshSystemState() },
            revealCaptures: { NSWorkspace.shared.activateFileViewerSelecting([store.directory]) },
            purgeAll: { Task { await model.purgeAll() } }
        )
    }
}
