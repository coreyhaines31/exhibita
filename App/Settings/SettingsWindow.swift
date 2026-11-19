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
    private var window: NSWindow?
    private var observer: NSObjectProtocol?

    init(model: AppModel, actions: SettingsActions, policy: CapturePolicyModel? = nil,
         policyActions: PolicyActions = PolicyActions(), refresh: @escaping () -> Void) {
        self.model = model
        self.actions = actions
        self.policy = policy
        self.policyActions = policyActions
        self.refresh = refresh
    }

    func show() {
        refresh()
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
                                                                    policyActions: policyActions))
        controller.sizingOptions = .preferredContentSize
        let window = NSWindow(contentViewController: controller)
        window.title = "\(Brand.name) Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        observer = NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window,
                                                          queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        return window
    }
}
