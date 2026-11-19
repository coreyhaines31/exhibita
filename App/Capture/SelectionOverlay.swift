import AppKit
import ExhibitShell

/// The dimmed overlay after a hotkey: drag for a region, Space to pick a window, ↩ for the whole screen under
/// the pointer, Esc to cancel. It shows each display's still from the hotkey (`FrozenScreen`), so the screen
/// looks frozen and what is selected is what was there. One borderless non-activating panel per display, so the
/// app under it keeps focus; Esc gives the key back to whichever of Exhibit A's windows had it. The geometry is
/// `SelectionGeometry` and `WindowPicker`; this class only routes events and draws.
@MainActor
final class SelectionOverlay {
    enum Outcome {
        case region(CaptureRegion)
        case window(WindowCandidate)
        case cancelled
    }

    enum Mode {
        case region
        case window
    }

    private var panels: [OverlayPanel] = []
    private var completion: ((Outcome) -> Void)?
    private var displays: [DisplayGeometry] = []
    private var windowList: [WindowCandidate] = []
    private var mainDisplayHeight: CGFloat = 0
    private weak var previousKey: NSWindow?
    private(set) var mode = Mode.region
    private(set) var dragStart: CGPoint?
    private(set) var dragCurrent: CGPoint?
    private(set) var hovered: WindowCandidate?
    /// What the panels show while the overlay is up.
    private(set) var frozen: FrozenScreen?

    var isActive: Bool { completion != nil }

    /// The panels while the overlay is up, one per display.
    var windows: [NSPanel] { panels }

    func begin(_ frozen: FrozenScreen, completion: @escaping (Outcome) -> Void) {
        guard !isActive else { return }
        self.completion = completion
        self.frozen = frozen
        mainDisplayHeight = frozen.mainDisplayHeight
        displays = frozen.displays
        // The windows at the hotkey, Exhibit A's own included: the overlay is not among them.
        windowList = frozen.windows
        mode = .region
        dragStart = nil
        dragCurrent = nil
        hovered = nil
        previousKey = NSApp.keyWindow
        let mouse = NSEvent.mouseLocation
        panels = frozen.stills.map { OverlayPanel(still: $0, overlay: self) }
        for panel in panels {
            panel.orderFrontRegardless()
        }
        let key = panels.first { $0.frame.contains(mouse) } ?? panels.first
        key?.makeKey()
        NSCursor.crosshair.push()
    }

    /// Closes the overlay as Esc does.
    func cancel() {
        finish(.cancelled)
    }

    private func finish(_ outcome: Outcome) {
        guard let completion else { return }
        self.completion = nil
        NSCursor.pop()
        for panel in panels {
            panel.orderOut(nil)
        }
        panels.removeAll()
        if case .cancelled = outcome, let previousKey, previousKey.isVisible {
            previousKey.makeKey()
        }
        previousKey = nil
        frozen = nil
        completion(outcome)
    }

    private func redraw() {
        for panel in panels {
            panel.contentView?.subviews.forEach { $0.needsDisplay = true }
        }
    }

    // MARK: - Events, in global Cocoa points

    func mouseDown(at point: CGPoint) {
        switch mode {
        case .window:
            if let hovered { finish(.window(hovered)) }
        case .region:
            dragStart = point
            dragCurrent = point
        }
    }

    func mouseDragged(to point: CGPoint) {
        guard mode == .region, dragStart != nil else { return }
        dragCurrent = point
        redraw()
    }

    func mouseUp(at point: CGPoint) {
        guard mode == .region, let start = dragStart else { return }
        dragStart = nil
        dragCurrent = nil
        guard let display = SelectionGeometry.display(containing: start, in: displays),
              let region = SelectionGeometry.region(for: SelectionGeometry.rect(from: start, to: point), on: display)
        else {
            redraw()
            return
        }
        finish(.region(region))
    }

    func mouseMoved(to point: CGPoint) {
        guard mode == .window else { return }
        let cgPoint = SelectionGeometry.coreGraphicsPoint(fromCocoa: point, mainDisplayHeight: mainDisplayHeight)
        let picked = WindowPicker.pick(at: cgPoint, in: windowList)
        if picked != hovered {
            hovered = picked
            redraw()
        }
    }

    /// Returns whether the key was handled.
    func keyDown(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 0x35: // Esc
            finish(.cancelled)
        case 0x31: // Space
            mode = mode == .region ? .window : .region
            dragStart = nil
            dragCurrent = nil
            hovered = nil
            mouseMoved(to: NSEvent.mouseLocation)
            redraw()
        case 0x24, 0x4C: // Return, Enter
            let mouse = NSEvent.mouseLocation
            guard let display = SelectionGeometry.display(containing: mouse, in: displays) ?? displays.first else {
                finish(.cancelled)
                return true
            }
            finish(.region(SelectionGeometry.fullScreen(display)))
        default:
            return false
        }
        return true
    }

    // MARK: - What the views draw

    /// The selection in global Cocoa points while dragging.
    var selection: CGRect? {
        guard let dragStart, let dragCurrent else { return nil }
        return SelectionGeometry.rect(from: dragStart, to: dragCurrent)
    }

    /// The hovered window in global Cocoa points.
    var hoveredFrame: CGRect? {
        hovered.map { SelectionGeometry.cocoaRect(fromCoreGraphics: $0.frame, mainDisplayHeight: mainDisplayHeight) }
    }
}

extension NSScreen {
    var displayID: UInt32? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}

/// A borderless panel over one display, showing its still. Non-activating, so the frontmost app stays
/// frontmost, but it can take key so Esc, Space and ↩ reach it.
private final class OverlayPanel: NSPanel {
    init(still: DisplayStill, overlay: SelectionOverlay) {
        let frame = still.display.frame
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
                   defer: false)
        setFrame(frame, display: false)
        level = .screenSaver
        isOpaque = true
        backgroundColor = .black
        hasShadow = false
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        let content = StillView(image: still.image, size: frame.size)
        let view = OverlayView(overlay: overlay, screenFrame: frame)
        view.autoresizingMask = [.width, .height]
        content.addSubview(view)
        contentView = content
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// The display's still, as the layer's contents, so the compositor scales it and a drag redraws only the dim
/// above it.
private final class StillView: NSView {
    private let image: CGImage

    init(image: CGImage, size: CGSize) {
        self.image = image
        super.init(frame: CGRect(origin: .zero, size: size))
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.contentsGravity = .resize
        layer?.contents = image
    }
}

private final class OverlayView: NSView {
    private weak var overlay: SelectionOverlay?
    private let screenFrame: CGRect

    init(overlay: SelectionOverlay, screenFrame: CGRect) {
        self.overlay = overlay
        self.screenFrame = screenFrame
        super.init(frame: CGRect(origin: .zero, size: screenFrame.size))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    private func global(_ event: NSEvent) -> CGPoint {
        let local = convert(event.locationInWindow, from: nil)
        return CGPoint(x: local.x + screenFrame.minX, y: local.y + screenFrame.minY)
    }

    private func local(_ rect: CGRect) -> CGRect {
        rect.offsetBy(dx: -screenFrame.minX, dy: -screenFrame.minY)
    }

    override func mouseDown(with event: NSEvent) { overlay?.mouseDown(at: global(event)) }
    override func mouseDragged(with event: NSEvent) { overlay?.mouseDragged(to: global(event)) }
    override func mouseUp(with event: NSEvent) { overlay?.mouseUp(at: global(event)) }
    override func mouseMoved(with event: NSEvent) { overlay?.mouseMoved(to: global(event)) }

    override func keyDown(with event: NSEvent) {
        if overlay?.keyDown(event) != true { super.keyDown(with: event) }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let overlay else { return }
        let dim = NSBezierPath(rect: bounds)
        var cutout: CGRect?
        switch overlay.mode {
        case .region: cutout = overlay.selection.map(local)
        case .window: cutout = overlay.hoveredFrame.map(local)
        }
        if let cutout {
            dim.append(NSBezierPath(rect: cutout))
            dim.windingRule = .evenOdd
        }
        NSColor.black.withAlphaComponent(0.35).setFill()
        dim.fill()
        if let cutout {
            NSColor.white.withAlphaComponent(0.9).setStroke()
            let border = NSBezierPath(rect: cutout.insetBy(dx: -0.5, dy: -0.5))
            border.lineWidth = 1
            border.stroke()
            if overlay.mode == .region { drawSize(of: cutout) }
        }
        drawHint(mode: overlay.mode)
    }

    private func drawSize(of rect: CGRect) {
        let text = "\(Int(rect.width.rounded())) × \(Int(rect.height.rounded()))" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let size = text.size(withAttributes: attributes)
        var origin = CGPoint(x: rect.maxX - size.width - 6, y: rect.minY - size.height - 8)
        if origin.y < 4 { origin.y = rect.minY + 6 }
        let plate = CGRect(x: origin.x - 5, y: origin.y - 2, width: size.width + 10, height: size.height + 4)
        NSColor.black.withAlphaComponent(0.75).setFill()
        NSBezierPath(roundedRect: plate, xRadius: 3, yRadius: 3).fill()
        text.draw(at: origin, withAttributes: attributes)
    }

    private func drawHint(mode: SelectionOverlay.Mode) {
        let hint = mode == .region
            ? "Drag to select    Space: window    ↩: whole screen    Esc: cancel"
            : "Click a window    Space: back to region    Esc: cancel"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let text = hint as NSString
        let size = text.size(withAttributes: attributes)
        let origin = CGPoint(x: bounds.midX - size.width / 2, y: 48)
        let plate = CGRect(x: origin.x - 12, y: origin.y - 6, width: size.width + 24, height: size.height + 12)
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: plate, xRadius: 6, yRadius: 6).fill()
        text.draw(at: origin, withAttributes: attributes)
    }
}
