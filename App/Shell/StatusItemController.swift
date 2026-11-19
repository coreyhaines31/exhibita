import AppKit
import SwiftUI

/// The menu bar glyph and the panel it opens.
@MainActor
final class StatusItemController {
    private static let autosaveName = "ExhibitA"
    private let item: NSStatusItem
    private let popover: NSPopover
    private let hosting: NSHostingController<PanelView>
    private let willShow: () -> Void

    init(model: AppModel, actions: PanelActions, willShow: @escaping () -> Void) {
        self.willShow = willShow
        // New status items start at the far left on recent macOS, which is off-screen on a crowded menu bar.
        UserDefaults.standard.register(defaults: ["NSStatusItem Preferred Position \(Self.autosaveName)": 1])
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.item = item
        item.autosaveName = Self.autosaveName
        item.button?.image = Glyph.image()
        item.button?.toolTip = Brand.name

        var panelActions = actions
        let popover = NSPopover()
        self.popover = popover
        let openSettings = actions.openSettings
        panelActions.openSettings = {
            popover.performClose(nil)
            openSettings()
        }
        let hosting = NSHostingController(rootView: PanelView(model: model, actions: panelActions))
        hosting.sizingOptions = .preferredContentSize
        self.hosting = hosting
        popover.contentViewController = hosting
        popover.behavior = .transient

        item.button?.target = self
        item.button?.action = #selector(toggle)
    }

    @objc private func toggle() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            show()
        }
    }

    var isShown: Bool { popover.isShown }

    func show() {
        guard let button = item.button else { return }
        willShow()
        popover.contentSize = hosting.view.fittingSize
        if !popover.isShown {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
        popover.contentViewController?.view.window?.makeKey()
    }

    func close() {
        popover.performClose(nil)
    }

    /// Blinks the glyph twice, so a person sees that an agent just captured the screen. Changes only the
    /// button's opacity: nothing activates and focus stays where it is.
    func flash() {
        guard let button = item.button else { return }
        Task { @MainActor in
            for _ in 0..<2 {
                button.alphaValue = 0.2
                try? await Task.sleep(for: .milliseconds(160))
                button.alphaValue = 1
                try? await Task.sleep(for: .milliseconds(160))
            }
        }
    }
}
