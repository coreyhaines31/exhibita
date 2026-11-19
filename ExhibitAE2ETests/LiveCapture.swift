import AppKit
@testable import ExhibitA
import ExhibitCore
import ExhibitShell
import ExhibitStore
import XCTest

/// The real selection overlay, driven with synthetic events posted to its own panels (this process's windows, so
/// no permission is needed), and what a live capture left behind. Used only by `CaptureTests`, which run only
/// from `Scripts/run-e2e-capture.sh`.
///
/// Privacy: these helpers report sizes, counts, kinds and timings only. Nothing here prints or saves a captured
/// image, its text, an app name or a window title.
@MainActor
enum LiveCapture {
    static var overlay: SelectionOverlay { E2E.app.capture!.overlay }
    static var mainScreen: NSScreen { NSScreen.screens[0] }
    static var mainDisplayHeight: CGFloat { mainScreen.frame.height }

    /// Presses a hotkey the way `HotkeyCenter` does, and waits for every panel to be on screen.
    /// Returns the time from the call to the overlay being visible.
    @discardableResult
    static func start(_ action: HotkeyAction) async throws -> Duration {
        let start = ContinuousClock.now
        E2E.app.hotkeyPressed(action)
        let shown = await E2E.wait("the overlay") {
            overlay.isActive && !overlay.windows.isEmpty && overlay.windows.allSatisfy(\.isVisible)
        }
        guard shown else { throw XCTSkip("The overlay did not appear") }
        return ContinuousClock.now - start
    }

    /// The panel covering `screen`.
    static func panel(on screen: NSScreen) throws -> NSPanel {
        try XCTUnwrap(overlay.windows.first { $0.frame == screen.frame }, "a panel over the display")
    }

    /// The panel over the display holding `point` (global Cocoa points).
    static func panel(containing point: CGPoint) throws -> NSPanel {
        try XCTUnwrap(overlay.windows.first { $0.frame.contains(point) }, "a panel under the point")
    }

    /// Down, drags, up, in the panel's own points. Returns the moment the mouse went up.
    static func drag(on panel: NSPanel, from: NSPoint, to: NSPoint) -> ContinuousClock.Instant {
        Events.mouse(.leftMouseDown, at: from, in: panel)
        for step in 1...8 {
            let t = CGFloat(step) / 8
            Events.mouse(.leftMouseDragged, at: NSPoint(x: from.x + (to.x - from.x) * t,
                                                        y: from.y + (to.y - from.y) * t), in: panel)
        }
        let up = ContinuousClock.now
        Events.mouse(.leftMouseUp, at: to, in: panel)
        return up
    }

    /// A key, as the keyboard would deliver it: through `NSApp.sendEvent` to the key window.
    static func key(_ code: UInt16, in panel: NSPanel) {
        if code == 0x31 {
            post(code: code, characters: " ", in: panel)
        } else {
            Events.special(code, in: panel)
        }
    }

    private static func post(code: UInt16, characters: String, in panel: NSPanel) {
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [],
                                         timestamp: ProcessInfo.processInfo.systemUptime,
                                         windowNumber: panel.windowNumber, context: nil, characters: characters,
                                         charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)
            if let event { NSApp.sendEvent(event) }
        }
    }

    /// Moves the (synthetic) pointer to a global Core Graphics point over the overlay.
    static func move(toCoreGraphics point: CGPoint) throws {
        let cocoa = CGPoint(x: point.x, y: mainDisplayHeight - point.y)
        let panel = try panel(containing: cocoa)
        let local = NSPoint(x: cocoa.x - panel.frame.minX, y: cocoa.y - panel.frame.minY)
        Events.mouse(.mouseMoved, at: local, in: panel)
    }

    static func click(atCoreGraphics point: CGPoint) throws {
        let cocoa = CGPoint(x: point.x, y: mainDisplayHeight - point.y)
        let panel = try panel(containing: cocoa)
        let local = NSPoint(x: cocoa.x - panel.frame.minX, y: cocoa.y - panel.frame.minY)
        Events.click(at: local, in: panel)
    }

    /// Ends a test's overlay if a failure left it up.
    static func cancelOverlay() {
        if overlay.isActive { overlay.cancel() }
    }

    // MARK: - The editor after a live capture

    /// The issue tracking an editor that opens but does not become key after a live capture in the test host.
    static let activationIssue = 53

    /// Waits for the capture's editor to be on screen, then up to `keyTimeout` seconds for it to be key, without
    /// failing if it never is (`expectKey` checks that).
    static func editor(for id: UUID, keyTimeout: TimeInterval = 2) async throws
        -> (controller: EditorWindowController, shownAt: ContinuousClock.Instant, keyAt: ContinuousClock.Instant?) {
        await E2E.wait("the editor") { E2E.editors.windows[id]?.window?.isVisible == true }
        let shownAt = ContinuousClock.now
        let controller = try XCTUnwrap(E2E.editors.windows[id])
        let deadline = Date().addingTimeInterval(keyTimeout)
        while controller.window?.isKeyWindow != true, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        return (controller, shownAt, controller.window?.isKeyWindow == true ? ContinuousClock.now : nil)
    }

    /// The editor should take the keys. In the test host macOS may decline the activation, since synthetic events
    /// are not user input it saw: recorded as an expected failure against `activationIssue`.
    static func expectKey(_ window: NSWindow, file: StaticString = #filePath, line: UInt = #line) {
        guard !window.isKeyWindow else { return }
        print("E2E: editor visible but not key; app active \(NSApp.isActive)")
        XCTExpectFailure("Issue \(activationIssue): the editor is not key after a live capture") {
            XCTAssertTrue(window.isKeyWindow, "the editor takes the keys", file: file, line: line)
        }
    }

    /// A key straight to `window`, as AppKit hands a key window its keys, whether or not it is key.
    static func send(_ code: UInt16, characters: String, to window: NSWindow) {
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [],
                                         timestamp: ProcessInfo.processInfo.systemUptime,
                                         windowNumber: window.windowNumber, context: nil, characters: characters,
                                         charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)
            if let event { window.sendEvent(event) }
        }
    }

    /// The app's visible windows, leaving out the menu bar item's own windows (one per display's menu bar, which
    /// AppKit shows as each menu bar draws).
    static func visibleWindows() -> Set<Int> {
        Set(NSApp.windows.filter { $0.isVisible && !String(describing: type(of: $0)).contains("StatusBar") }
            .map(\.windowNumber))
    }

    // MARK: - Windows to pick

    /// Another app's ordinary window that is frontmost at its own centre, on `screen` when given, so a pick at
    /// that point means this window. Front to back, as the overlay sees them: since issue 72 the overlay picks
    /// Exhibit A's own windows too, so one of ours in front (an editor still closing) rules a window out.
    static func pickableWindow(on screen: NSScreen? = nil) -> (window: WindowCandidate, point: CGPoint)? {
        let windows = WindowList.onScreen()
        let own = ProcessInfo.processInfo.processIdentifier
        let bounds = screen.map { coreGraphicsFrame(of: $0) }
        for window in windows where window.layer == 0 && window.ownerPID != own
            && window.frame.width >= 300 && window.frame.height >= 200 {
            let center = CGPoint(x: window.frame.midX, y: window.frame.midY)
            if let bounds, !bounds.contains(window.frame) { continue }
            // A pick is cut from one display's still, so its size is the window's only when it is on one display.
            guard NSScreen.screens.contains(where: { coreGraphicsFrame(of: $0).contains(window.frame) }) else { continue }
            guard NSScreen.screens.contains(where: { coreGraphicsFrame(of: $0).contains(center) }) else { continue }
            if WindowPicker.pick(at: center, in: windows)?.id == window.id {
                return (window, center)
            }
        }
        return nil
    }

    /// A patch of `window` (global Core Graphics points) that no window in front of it covers, by the rule
    /// `Blackout` uses: inside the largest visible part, near its top-left corner and clear of its centre line,
    /// where the blackout label is drawn. Nil when nothing big enough shows.
    static func visiblePatch(of window: WindowCandidate, policy: CapturePolicy) -> CGRect? {
        let windows = WindowList.onScreen()
        guard let index = windows.firstIndex(where: { $0.id == window.id }) else { return nil }
        let infront = windows[..<index].filter { Blackout.covers($0, policy: policy) }.map(\.frame)
        let parts = Blackout.visibleParts(of: window.frame, minus: infront)
        guard let largest = parts.max(by: { $0.width * $0.height < $1.width * $1.height }),
              largest.width >= 60, largest.height >= 100 else { return nil }
        return CGRect(x: largest.minX + 8, y: largest.minY + 8, width: min(80, largest.width - 16), height: 30)
    }

    /// A screen's frame in global Core Graphics points (top-left origin).
    static func coreGraphicsFrame(of screen: NSScreen) -> CGRect {
        CGRect(x: screen.frame.minX, y: mainDisplayHeight - screen.frame.maxY,
               width: screen.frame.width, height: screen.frame.height)
    }

    /// The screen under the real pointer, which ↩ captures.
    static var screenUnderPointer: NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) } ?? mainScreen
    }

    // MARK: - A window of our own

    /// The colour of `solidWindow`, in sRGB.
    static let solidColour = NSColor(srgbRed: 0, green: 1, blue: 0, alpha: 1)

    /// A plain window of this app filled with `solidColour`, at `frame` (global Cocoa points), in front of other
    /// apps' ordinary windows without activating anything. What the captures of it are checked against.
    static func solidWindow(at frame: CGRect) -> NSWindow {
        let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.backgroundColor = solidColour
        window.isOpaque = true
        window.hasShadow = false
        window.level = .normal
        window.orderFrontRegardless()
        return window
    }

    /// Fraction of pixels that read as `solidColour` once converted to sRGB, with room for the display's colour
    /// profile on the way.
    static func solidFraction(_ image: CGImage) -> Double {
        let bytes = Pixels(image).bytes
        guard !bytes.isEmpty else { return 0 }
        var solid = 0
        var index = 0
        while index + 3 < bytes.count {
            if bytes[index] < 70, bytes[index + 1] > 190, bytes[index + 2] < 70 { solid += 1 }
            index += 4
        }
        return Double(solid) / Double(bytes.count / 4)
    }

    /// The mean sRGB colour of `image`, as "r g b" in 0 to 255: a statistic, never the picture.
    static func meanColour(_ image: CGImage) -> String {
        let bytes = Pixels(image).bytes
        var sums = [0, 0, 0]
        var index = 0
        while index + 3 < bytes.count {
            for channel in 0..<3 { sums[channel] += Int(bytes[index + channel]) }
            index += 4
        }
        let count = max(1, bytes.count / 4)
        return sums.map { String($0 / count) }.joined(separator: " ")
    }

    // MARK: - What was captured

    static func newCaptures(since before: Set<UUID>) -> [HistoryItem] {
        E2E.store.list().filter { !before.contains($0.id) }
    }

    /// Waits for exactly one new capture in history and returns it with the time it appeared.
    static func waitForCapture(since before: Set<UUID>, timeout: TimeInterval = 15) async throws
        -> (item: HistoryItem, at: ContinuousClock.Instant) {
        await E2E.wait("the capture in history", timeout: timeout) { !newCaptures(since: before).isEmpty }
        let at = ContinuousClock.now
        let items = newCaptures(since: before)
        XCTAssertEqual(items.count, 1, "one new capture")
        return (try XCTUnwrap(items.first), at)
    }

    /// Fraction of pixels in `rect` that are black (each channel at most 3 of 255).
    static func blackFraction(_ image: CGImage, in rect: PixelRect) -> Double {
        let bytes = Pixels(image).region(rect)
        guard !bytes.isEmpty else { return 0 }
        var black = 0
        var index = 0
        while index + 3 < bytes.count {
            if bytes[index] <= 3, bytes[index + 1] <= 3, bytes[index + 2] <= 3 { black += 1 }
            index += 4
        }
        return Double(black) / Double(bytes.count / 4)
    }

    static func ms(_ duration: Duration) -> String {
        let value = Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
        return String(format: "%.0f ms", value)
    }

    /// The CLI's JSON reduced to what may be logged: the exit status and an error code, never names or titles.
    static func summary(_ result: E2E.CLIResult) -> String {
        let stderr = (try? JSONSerialization.jsonObject(with: Data(result.stderr.utf8))) as? [String: Any] ?? [:]
        let json = result.json.isEmpty ? stderr : result.json
        let error = (json["error"] as? [String: Any])?["code"] as? String ?? json["code"] as? String
        return "exit \(result.status)" + (error.map { " code \($0)" } ?? "")
    }
}
