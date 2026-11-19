import AppKit
import ExhibitEditor
import ExhibitShell
import ExhibitStore
import os
import PanelKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private nonisolated static let logger = Logger(subsystem: Brand.bundleIdentifier, category: "App")

    private(set) var model: AppModel?
    private(set) var statusItem: StatusItemController?
    private var settingsWindow: SettingsWindow?
    private var hotkeys: HotkeyCenter?
    private(set) var capture: CaptureController?
    private(set) var editors: EditorWindows?
    private(set) var bridge: BridgeHost?
    /// The never-capture list and auto-blur, as Settings edits them.
    private(set) var policy: CapturePolicyModel?
    private let updater = Updater()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Debug builds under the end-to-end tests: throwaway support directory and settings, before anything reads them.
        TestSeam.applyDefaults()
        if TestSeam.isActive, !TestSeam.allowsCapture { ScreenRecording.forcedOff = true }
        PanelFont.register()
        if !TestSeam.isActive { LaunchAtLogin.applyDefault() }
        updater.start()

        let store = CaptureStore(directory: (try? TestSeam.capturesDirectory())
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

        // Every document write for a capture the editor may have open goes through `OpenCaptures`.
        let editors = EditorWindows(model: model, captures: OpenCaptures(store: store))
        self.editors = editors
        // The never-capture list and auto-blur, one file for people and agents alike.
        let support = store.directory.deletingLastPathComponent()
        let policy = CapturePolicyModel(file: CapturePolicyFile(supportDirectory: support))
        self.policy = policy
        let capture = CaptureController(model: model, editors: editors)
        capture.policy = { [snapshot = policy.snapshot] in snapshot.current }
        self.capture = capture
        let hotkeys = HotkeyCenter { [weak self] action in
            self?.hotkeyPressed(action)
        }
        // The tests call `hotkeyPressed` themselves: registering would take the keys from the real app.
        if !TestSeam.isActive { hotkeys.install(model.bindings) }
        model.onBindingsChanged = { [weak hotkeys] in hotkeys?.apply($0) }
        self.hotkeys = hotkeys

        let actions = settingsActions(model: model, store: store)
        let policyActions = PolicyActions(runningApps: { AppPicker.runningApps() },
                                          chooseApp: { AppPicker.choose { policy.add($0) } })
        let settingsWindow = SettingsWindow(model: model, actions: actions, policy: policy,
                                            policyActions: policyActions,
                                            updates: updater.settings) { [weak self] in
            self?.refreshSystemState()
        }
        self.settingsWindow = settingsWindow
        let statusItem = makeStatusItem(model: model)
        self.statusItem = statusItem
        wire(capture, to: statusItem)
        editors.willOpen = { [weak statusItem] in statusItem?.close() }
        editors.openSettings = { [weak settingsWindow] in settingsWindow?.show() }
        model.onKeymapChanged = { [weak editors] in editors?.apply($0) }
        startBridge(store: store, support: support, policy: policy, model: model, captures: editors.captures)

        Task { await model.reload() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Marks are saved within 100 ms of every change anyway; this writes the last few.
        editors?.flushAll()
        bridge?.stop()
    }

    /// The capture's hold on the panel: open for permission and refusals, held through the overlay, closed once
    /// a capture is taken.
    private func wire(_ capture: CaptureController, to statusItem: StatusItemController) {
        capture.showPanel = { [weak statusItem] in statusItem?.show() }
        capture.closePanel = { [weak statusItem] in statusItem?.close() }
        capture.holdPanel = { [weak statusItem] in statusItem?.holdOpen($0) }
        capture.didFinish = { [weak self] in self?.refreshSystemState() }
    }

    /// What either global hotkey does. Nothing on screen changes first: the capture freezes the screen, and the
    /// panel and the system state are left alone until the overlay is done.
    func hotkeyPressed(_ action: HotkeyAction) {
        capture?.start(action)
    }

    /// Live captures for `exhibit capture`, without the overlay and without moving focus.
    private func startBridge(store: CaptureStore, support: URL, policy: CapturePolicyModel, model: AppModel,
                             captures: OpenCaptures) {
        let bridge = BridgeHost(store: store, supportDirectory: support, policy: policy.snapshot,
                                captures: captures,
                                present: { [weak self] id in
                                    // `exhibit open`: the one place a capture is handed to the person.
                                    guard let editors = self?.editors else { return false }
                                    editors.open(id)
                                    return true
                                },
                                didCapture: { [weak self] _ in
                                    self?.statusItem?.flash()
                                    await model.reload()
                                })
        bridge.start()
        self.bridge = bridge
    }

    /// Permission and the system shortcuts can change in System Settings at any time. They are read again when
    /// the panel, Settings or a hotkey needs them, never on a timer.
    private func refreshSystemState() {
        guard let model else { return }
        model.permission = ScreenRecording.state
        model.updateSystemShortcuts(SystemShortcuts.read())
    }

    /// The menu bar item and its panel, which reads the system state and history again each time it opens.
    private func makeStatusItem(model: AppModel) -> StatusItemController {
        StatusItemController(model: model, actions: panelActions(model: model), updates: updater.settings) { [weak self] in
            self?.refreshSystemState()
            Task { await model.reload() }
        }
    }

    private func panelActions(model: AppModel) -> PanelActions {
        PanelActions(
            openSettings: { [weak self] in self?.settingsWindow?.show() },
            openHotkeySettings: { [weak self] in self?.settingsWindow?.show(at: .hotkeys) },
            quit: { NSApp.terminate(nil) },
            allowScreenRecording: { ScreenRecording.request() },
            checkPermissionAgain: { [weak self] in self?.refreshSystemState() },
            openKeyboardSettings: { SystemShortcuts.openKeyboardSettings() },
            open: { [weak self] in self?.editors?.open($0) },
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
