import AppKit
import SwiftUI

/// The menu bar glyph and the panel it opens.
@MainActor
final class StatusItemController {
    private static let autosaveName = "ExhibitA"
    let item: NSStatusItem
    private let popover: NSPopover
    private let hosting: NSHostingController<PanelView>
    private let willShow: () -> Void
    /// Where the panel's rows and their buttons were laid out, for the end-to-end tests.
    let frames: PanelFrames

    init(model: AppModel, actions: PanelActions, willShow: @escaping () -> Void) {
        self.willShow = willShow
        // New status items start at the far left on recent macOS, which is off-screen on a crowded menu bar.
        UserDefaults.standard.register(defaults: ["NSStatusItem Preferred Position \(Self.autosaveName)": 1])
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.item = item
        // Under the end-to-end tests the item's position would be saved into the real app's settings.
        if !TestSeam.isActive { item.autosaveName = Self.autosaveName }
        item.button?.image = Glyph.image()
        item.button?.toolTip = Brand.name

        var panelActions = actions
        let frames = PanelFrames()
        self.frames = frames
        panelActions.reportFrame = { frames.byName[$0] = $1 }
        let popover = NSPopover()
        self.popover = popover
        let openSettings = actions.openSettings
        panelActions.openSettings = {
            popover.performClose(nil)
            openSettings()
        }
        let openHotkeySettings = actions.openHotkeySettings
        panelActions.openHotkeySettings = {
            popover.performClose(nil)
            openHotkeySettings()
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
    /// The panel's content, for the end-to-end tests' events and pictures.
    var panelView: NSView? { popover.contentViewController?.view }

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

    /// While held, the panel stays open whatever is clicked: the capture overlay sits over it.
    func holdOpen(_ hold: Bool) {
        popover.behavior = hold ? .applicationDefined : .transient
    }

    /// How many times `flash` has run, for the end-to-end tests.
    private(set) var flashes = 0

    /// Blinks the glyph twice, so a person sees that an agent just captured the screen. Changes only the
    /// button's opacity: nothing activates and focus stays where it is.
    func flash() {
        guard let button = item.button else { return }
        flashes += 1
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

/// The panel's reported layout: name to frame, top-left origin, in the panel's coordinates.
@MainActor
final class PanelFrames {
    var byName: [String: CGRect] = [:]
}
