import AppKit
import SwiftUI

/// The Settings window. macOS's screenshot shortcuts and Screen Recording are read again whenever it comes
/// forward, so changes made in System Settings show up without polling.
@MainActor
final class SettingsWindow {
    private let model: AppModel
    private let actions: SettingsActions
    private let refresh: () -> Void
    private let policy: CapturePolicyModel?
    private let policyActions: PolicyActions
    private let updates: UpdateSettings
    private var window: NSWindow?
    private let navigation = SettingsNavigation()
    private var observer: NSObjectProtocol?

    init(model: AppModel, actions: SettingsActions, policy: CapturePolicyModel? = nil,
         policyActions: PolicyActions = PolicyActions(), updates: UpdateSettings = UpdateSettings(),
         refresh: @escaping () -> Void) {
        self.model = model
        self.actions = actions
        self.policy = policy
        self.policyActions = policyActions
        self.updates = updates
        self.refresh = refresh
    }

    /// Brings Settings forward, scrolled to `anchor` when given.
    func show(at anchor: SettingsAnchor? = nil) {
        refresh()
        if let anchor { navigation.go(to: anchor) }
        if window == nil { window = makeWindow() }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
        // A menu bar app isn't active when its panel opens Settings, and macOS 14's cooperative activate() can
        // be declined. A window that isn't key spends the first click on becoming key, so insist.
        DispatchQueue.main.async { [weak self] in
            guard let window = self?.window, !window.isKeyWindow || !NSApp.isActive else { return }
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
    }

    private func makeWindow() -> NSWindow {
        let controller = NSHostingController(rootView: SettingsView(model: model, actions: actions, policy: policy,
                                                                    policyActions: policyActions,
                                                                    updates: updates,
                                                                    navigation: navigation,
                                                                    fitsContent: false))
        // The form is far taller than a laptop screen, so the window takes a height that fits the screen and the
        // form scrolls inside it.
        controller.sizingOptions = []
        let window = NSWindow(contentViewController: controller)
        window.title = "\(Brand.name) Settings"
        window.styleMask = [.titled, .closable, .resizable]
        window.isReleasedWhenClosed = false
        let screen = NSScreen.main ?? NSScreen.screens.first
        let height = SettingsView.windowHeight(onScreenOfHeight: screen?.visibleFrame.height)
        window.setContentSize(NSSize(width: SettingsView.width, height: height))
        window.contentMinSize = NSSize(width: SettingsView.width, height: SettingsView.minimumWindowHeight)
        window.contentMaxSize = NSSize(width: SettingsView.width, height: 10_000)
        window.center()
        observer = NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window,
                                                          queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        return window
    }
}
