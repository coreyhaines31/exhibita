import CoreGraphics
import ExhibitEditor
import ExhibitShell
import ExhibitStore
import Foundation
import Observation

/// What the panel and Settings show: history, permission, hotkeys and retention. File work runs off the main
/// thread; the app wires side effects (registering hotkeys, launch at login) through the closures.
@MainActor
@Observable
final class AppModel {
    let store: CaptureStore
    private(set) var items: [HistoryItem] = []
    private(set) var thumbnails: [UUID: CGImage] = [:]
    var selected: UUID?
    var permission: ScreenRecordingState
    private(set) var bindings: HotkeyBindings
    private(set) var retention: RetentionPolicy
    var launchesAtLogin: Bool
    /// Shown beside a hotkey after a refused change.
    private(set) var hotkeyMessages: [HotkeyAction: String] = [:]
    /// The editor's keys: the defaults with the person's changes on top.
    private(set) var keymap: EditorKeymap
    /// Shown under an editor key's row after a refused change, until the next change to that row.
    private(set) var shortcutMessages: [EditorCommand: String] = [:]
    /// Why the last window pick was not captured, shown at the top of the panel until dismissed or the next
    /// capture starts.
    private(set) var captureRefusal: String?

    /// A window pick the never-capture list refused. `reason` is `CapturePolicy`'s, such as "1Password is on the
    /// never-capture list".
    func refuseCapture(reason: String) {
        captureRefusal = "\(reason), so its window was not captured. Change the list in Settings, Privacy."
    }

    func clearCaptureRefusal() {
        captureRefusal = nil
    }

    /// Called after the hotkeys in effect change, so they can be registered again.
    @ObservationIgnored var onBindingsChanged: (HotkeyBindings) -> Void = { _ in }
    /// Called after the editor's keys change, so open editors use them at once.
    @ObservationIgnored var onKeymapChanged: (EditorKeymap) -> Void = { _ in }
    @ObservationIgnored var onLaunchAtLoginChanged: (Bool) -> Bool = { $0 }
    /// The time history is shown and swept against; renders fix it so their PNGs don't change from run to run.
    @ObservationIgnored var clock: () -> Date = { Date() }

    static let thumbnailPixels = 160

    init(store: CaptureStore, permission: ScreenRecordingState, system: SystemScreenshotShortcuts,
         launchesAtLogin: Bool) {
        self.store = store
        self.permission = permission
        bindings = HotkeyBindings(custom: Preferences.customHotkeys, system: system)
        retention = Preferences.retention
        keymap = Preferences.editorKeymap
        self.launchesAtLogin = launchesAtLogin
    }

    // MARK: - History

    /// Sweeps expired captures, then reads the list and any missing thumbnails.
    func reload() async {
        let store = store
        let policy = retention
        let now = clock()
        let known = Set(thumbnails.keys)
        let pixels = Self.thumbnailPixels
        let (items, newThumbnails) = await Task.detached(priority: .userInitiated) {
            _ = try? store.sweep(policy: policy, now: now)
            let items = store.list()
            var thumbnails: [UUID: CGImage] = [:]
            for item in items where !known.contains(item.id) {
                thumbnails[item.id] = store.thumbnail(for: item.id, maxPixelSize: pixels)
            }
            return (items, thumbnails)
        }.value
        apply(items: items, newThumbnails: newThumbnails)
    }

    /// Sets the list directly; tests and the snapshot fixtures use it.
    func apply(items: [HistoryItem], newThumbnails: [UUID: CGImage]) {
        self.items = items
        let ids = Set(items.map(\.id))
        thumbnails = thumbnails.filter { ids.contains($0.key) }.merging(newThumbnails) { _, new in new }
        if let selected, !ids.contains(selected) { self.selected = nil }
    }

    func delete(_ id: UUID) async {
        let store = store
        _ = await Task.detached { try? store.delete(id) }.value
        await reload()
    }

    func purgeAll() async {
        let store = store
        _ = await Task.detached { try? store.purgeAll() }.value
        await reload()
    }

    func setRetention(_ policy: RetentionPolicy) {
        retention = policy
        Preferences.retention = policy
        Task { await reload() }
    }

    var rows: [HistoryRow] {
        HistoryPresentation.rows(items, policy: retention, selected: selected, now: clock())
    }

    var content: PanelContent {
        PanelContent.resolve(permission: permission, historyCount: items.count)
    }

    var summary: String {
        HistoryPresentation.summary(count: items.count, policy: retention)
    }

    var emptyHint: String {
        HistoryPresentation.emptyHint(edit: bindings.combo(for: .captureAndEdit),
                                      clipboard: bindings.combo(for: .captureToClipboard))
    }

    // MARK: - Hotkeys

    func updateSystemShortcuts(_ system: SystemScreenshotShortcuts) {
        guard system != bindings.system else { return }
        bindings.system = system
        onBindingsChanged(bindings)
    }

    /// A key recorded in Settings. Refused keys leave the binding as it was and say why.
    func record(_ combo: KeyCombo?, for action: HotkeyAction) {
        if let combo, let issue = bindings.assign(combo, to: action) {
            hotkeyMessages[action] = issue.message
        } else {
            if combo == nil { bindings.reset(action) }
            hotkeyMessages[action] = nil
        }
        Preferences.customHotkeys = bindings.custom
        onBindingsChanged(bindings)
    }

    func resetHotkey(_ action: HotkeyAction) {
        bindings.reset(action)
        hotkeyMessages[action] = nil
        Preferences.customHotkeys = bindings.custom
        onBindingsChanged(bindings)
    }

    func message(for action: HotkeyAction) -> String? {
        hotkeyMessages[action] ?? bindings.issue(for: action)?.message
    }

    /// Exchanges the two hotkeys' keys, for anyone who has them the wrong way round in their head.
    func swapHotkeys() {
        bindings.swap()
        hotkeyMessages = [:]
        Preferences.customHotkeys = bindings.custom
        onBindingsChanged(bindings)
    }

    // MARK: - Editor keys

    /// A key pressed in a Shortcuts row's recorder. Refused keys leave the row as it was and say why.
    @discardableResult
    func recordShortcut(_ key: EditorKey, modifiers: KeyModifiers, for command: EditorCommand) -> Bool {
        if let issue = keymap.issue(recording: key, modifiers: modifiers, for: command) {
            shortcutMessages[command] = issue.message
            return false
        }
        guard let shortcut = EditorShortcut(key: key, modifiers: modifiers) else { return false }
        _ = keymap.assign(shortcut, to: command)
        shortcutMessages[command] = nil
        saveKeymap()
        return true
    }

    func resetShortcut(_ command: EditorCommand) {
        if let issue = keymap.reset(command) {
            shortcutMessages[command] = issue.message
            return
        }
        shortcutMessages[command] = nil
        saveKeymap()
    }

    func resetAllShortcuts() {
        keymap.resetAll()
        shortcutMessages = [:]
        saveKeymap()
    }

    /// What Settings shows under a row: a refusal, or a later default this row's key hides.
    func shortcutMessage(for command: EditorCommand) -> String? {
        if let message = shortcutMessages[command] { return message }
        guard let other = keymap.shadowing(command), let standard = command.defaultShortcut else { return nil }
        return "\(other.title) also uses \(standard.display), so pick another key here."
    }

    var shortcutRows: [ShortcutRow] {
        EditorCommand.remappable.map { command in
            ShortcutRow(command: command, title: command.title, detail: command.detail,
                        key: keymap.display(for: command), isCustom: keymap.isCustom(command),
                        message: shortcutMessage(for: command))
        }
    }

    private func saveKeymap() {
        Preferences.editorKeymap = keymap
        onKeymapChanged(keymap)
    }

    // MARK: - General

    func setLaunchAtLogin(_ enabled: Bool) {
        launchesAtLogin = onLaunchAtLoginChanged(enabled)
    }
}

/// One row of Settings, Shortcuts: an editor command and its key now.
struct ShortcutRow: Identifiable, Equatable {
    let command: EditorCommand
    let title: String
    let detail: String
    let key: String
    let isCustom: Bool
    let message: String?

    var id: String { command.id }
}
