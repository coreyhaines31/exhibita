import CoreGraphics
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

    /// Called after the hotkeys in effect change, so they can be registered again.
    @ObservationIgnored var onBindingsChanged: (HotkeyBindings) -> Void = { _ in }
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

    // MARK: - General

    func setLaunchAtLogin(_ enabled: Bool) {
        launchesAtLogin = onLaunchAtLoginChanged(enabled)
    }
}
