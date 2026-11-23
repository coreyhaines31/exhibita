import AppKit

/// Says "Copied to clipboard" after a capture that opens no window, so a capture that worked doesn't look like one
/// that failed, and what copy and delete or Copy Path did where no window is left to say it (issue 109). A small
/// panel low on the display the capture came from, gone after a moment. It never activates the app, takes key focus
/// or catches a click.
@MainActor
final class CopiedNote {
    static let text = "Copied to clipboard"
    static let visibleFor: Duration = .milliseconds(1400)

    /// How many times the note has been shown, for the end-to-end tests.
    private(set) var shown = 0
    /// The last thing it said, for the end-to-end tests.
    private(set) var lastText: String?
    private var panel: NSPanel?
    private var dismissal: Task<Void, Never>?

    func show(on screen: NSScreen?, text: String = CopiedNote.text) {
        guard let screen = screen ?? NSScreen.main else { return }
        shown += 1
        lastText = text
        dismissal?.cancel()
        panel?.orderOut(nil)

        let content = Self.makeContent(text)
        let size = content.fittingSize
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.contentView = content
        let visible = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2, y: visible.minY + visible.height * 0.14))
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        self.panel = panel

        dismissal = Task { [weak self] in
            try? await Task.sleep(for: Self.visibleFor)
            guard !Task.isCancelled else { return }
            await NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                panel.animator().alphaValue = 0
            }
            guard !Task.isCancelled else { return }
            panel.orderOut(nil)
            if self?.panel === panel { self?.panel = nil }
        }
    }

    /// Whether the note is on screen now.
    var isVisible: Bool { panel?.isVisible == true }

    /// Takes the note away at once, for the end-to-end tests between cases.
    func dismiss() {
        dismissal?.cancel()
        dismissal = nil
        panel?.orderOut(nil)
        panel = nil
    }

    private static func makeContent(_ text: String) -> NSView {
        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.state = .active
        effect.blendingMode = .behindWindow
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 12
        effect.layer?.masksToBounds = true

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
        icon.contentTintColor = .labelColor

        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.textColor = .labelColor

        let stack = NSStackView(views: [icon, label])
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 16, bottom: 12, right: 18)
        stack.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            stack.topAnchor.constraint(equalTo: effect.topAnchor),
            stack.bottomAnchor.constraint(equalTo: effect.bottomAnchor)
        ])
        effect.setFrameSize(effect.fittingSize)
        return effect
    }
}
