import AppKit
@testable import ExhibitA
import ExhibitCore
import ExhibitEditor
import ExhibitShell
import ExhibitStore
import XCTest

/// 8. Real captures of this Mac's screen, through the path the hotkey takes (`AppDelegate.hotkeyPressed`, the real
/// `SelectionOverlay`, ScreenCaptureKit) and through the bridge with the real `exhibit` binary. Run only from
/// `Scripts/run-e2e-capture.sh`; skipped otherwise, and skipped when the test host does not already have Screen
/// Recording (nothing here asks for it).
///
/// Privacy: captures stay in the temporary support directory. Assertions are on sizes, counts, kinds and pixel
/// statistics; nothing prints text read from a capture, an app name or a window title, and no picture is saved.
@MainActor
final class CaptureTests: XCTestCase {
    private var savedPasteboard: [NSPasteboardItem] = []

    override func setUp() async throws {
        try E2E.begin()
        guard TestSeam.allowsCapture else {
            throw XCTSkip("Real capture is off; Scripts/run-e2e-capture.sh turns it on")
        }
        guard ScreenRecording.isGranted else {
            throw XCTSkip("The test host does not have Screen Recording; nothing was asked for")
        }
        savedPasteboard = E2E.copyPasteboard()
    }

    override func tearDown() async throws {
        LiveCapture.cancelOverlay()
        E2E.closeEverything()
        E2E.restorePasteboard(savedPasteboard)
    }

    private var before: Set<UUID> { Set(E2E.store.list().map(\.id)) }

    // MARK: - Region

    func testRegionCaptureAndEdit() async throws {
        let known = before
        let toOverlay = try await LiveCapture.start(.captureAndEdit)
        let overlay = LiveCapture.overlay
        XCTAssertEqual(overlay.windows.count, NSScreen.screens.count, "one panel per display")
        for screen in NSScreen.screens {
            let panel = try LiveCapture.panel(on: screen)
            XCTAssertEqual(panel.level, .screenSaver)
            XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel), "non-activating")
            XCTAssertTrue(panel.isVisible)
        }
        XCTAssertTrue(overlay.windows.contains(where: \.isKeyWindow), "a panel takes the keys")

        let screen = LiveCapture.mainScreen
        let scale = screen.backingScaleFactor
        let panel = try LiveCapture.panel(on: screen)
        let up = LiveCapture.drag(on: panel, from: NSPoint(x: 200, y: 200), to: NSPoint(x: 600, y: 500))
        await E2E.wait("the overlay to close") { !overlay.isActive }
        XCTAssertFalse(panel.isVisible, "the overlay is gone")

        let (item, savedAt) = try await LiveCapture.waitForCapture(since: known)
        let shown = try await LiveCapture.editor(for: item.id)
        let loaded = try E2E.store.load(item.id)
        XCTAssertEqual(Double(loaded.original.width), 400 * scale, accuracy: 1, "pixels are points times scale")
        XCTAssertEqual(Double(loaded.original.height), 300 * scale, accuracy: 1)
        XCTAssertEqual(loaded.document.scale, Double(scale))
        XCTAssertEqual(loaded.document.size, PixelSize(width: loaded.original.width, height: loaded.original.height))
        XCTAssertEqual(loaded.document.source?.capturedBy, .person)
        let window = try XCTUnwrap(shown.controller.window)
        XCTAssertTrue(window.isVisible)
        LiveCapture.expectKey(window)

        LiveCapture.send(Events.escape, characters: "\u{1b}", to: window)
        await E2E.wait("Esc to close the editor") { E2E.editors.windows[item.id] == nil && !window.isVisible }
        print("E2E: timing hotkey to overlay visible \(LiveCapture.ms(toOverlay)) (stills of \(NSScreen.screens.count) "
              + "displays \(E2E.app.capture?.lastFreeze.map(LiveCapture.ms) ?? "unknown"))")
        print("E2E: timing mouse-up to capture saved \(LiveCapture.ms(savedAt - up))")
        print("E2E: timing mouse-up to editor visible \(LiveCapture.ms(shown.shownAt - up))")
        print("E2E: timing mouse-up to editor key "
              + (shown.keyAt.map { LiveCapture.ms($0 - up) } ?? "never (not key; issue \(LiveCapture.activationIssue))"))
    }

    func testRegionToClipboard() async throws {
        let known = before
        let pasteboard = NSPasteboard.general
        let changeCount = pasteboard.changeCount
        let notes = E2E.app.capture!.copiedNote.shown
        try await LiveCapture.start(.captureToClipboard)
        let scale = LiveCapture.mainScreen.backingScaleFactor
        let panel = try LiveCapture.panel(on: LiveCapture.mainScreen)
        let up = LiveCapture.drag(on: panel, from: NSPoint(x: 240, y: 160), to: NSPoint(x: 640, y: 460))
        await E2E.wait("the clipboard") { pasteboard.changeCount != changeCount }
        let copiedAt = ContinuousClock.now
        let png = try XCTUnwrap(pasteboard.data(forType: .png), "a PNG on the clipboard")
        let copied = try PNG.decode(png)
        XCTAssertEqual(Double(copied.width), 400 * scale, accuracy: 1)
        XCTAssertEqual(Double(copied.height), 300 * scale, accuracy: 1)
        let (item, _) = try await LiveCapture.waitForCapture(since: known)
        XCTAssertEqual(item.capturedBy, .person, "in history too")
        XCTAssertEqual(E2E.app.capture!.copiedNote.shown, notes + 1, "the copy is confirmed on screen")
        XCTAssertTrue(E2E.app.capture!.copiedNote.isVisible, "the note is up")
        XCTAssertFalse(NSApp.keyWindow.map { $0.level == .statusBar } ?? false, "the note never takes key")
        XCTAssertEqual(item.size, PixelSize(width: copied.width, height: copied.height))
        await E2E.settle(300)
        XCTAssertTrue(E2E.editors.windows.isEmpty, "no editor")
        print("E2E: timing mouse-up to clipboard \(LiveCapture.ms(copiedAt - up))")
    }

    /// Every display, at its own scale: a capture from each has that display's pixel size.
    func testRegionOnEveryDisplay() async throws {
        for (index, screen) in NSScreen.screens.enumerated() {
            let known = before
            try await LiveCapture.start(.captureToClipboard)
            let panel = try LiveCapture.panel(on: screen)
            _ = LiveCapture.drag(on: panel, from: NSPoint(x: 100, y: 100), to: NSPoint(x: 300, y: 250))
            let (item, _) = try await LiveCapture.waitForCapture(since: known)
            let scale = Double(screen.backingScaleFactor)
            XCTAssertEqual(Double(item.size.width), 200 * scale, accuracy: 1, "display \(index + 1)")
            XCTAssertEqual(Double(item.size.height), 150 * scale, accuracy: 1, "display \(index + 1)")
            XCTAssertEqual(item.scale, scale, "display \(index + 1)")
            print("E2E: display \(index + 1) of \(NSScreen.screens.count) at \(scale)x: \(item.size.width)x"
                  + "\(item.size.height) px")
        }
    }

    // MARK: - Whole screen and cancel

    func testReturnCapturesTheWholeDisplay() async throws {
        let known = before
        try await LiveCapture.start(.captureToClipboard)
        let screen = LiveCapture.screenUnderPointer
        let start = ContinuousClock.now
        LiveCapture.key(Events.returnKey, in: try LiveCapture.panel(on: screen))
        let (item, _) = try await LiveCapture.waitForCapture(since: known)
        let scale = Double(screen.backingScaleFactor)
        XCTAssertEqual(Double(item.size.width), screen.frame.width * scale, accuracy: 1)
        XCTAssertEqual(Double(item.size.height), screen.frame.height * scale, accuracy: 1)
        await E2E.wait("targets", timeout: 30) { !E2E.editors.captures.isFinding(item.id) }
        let targetsAt = ContinuousClock.now
        // The result is written to the bundle on the documents' serial queue just after; a screen with any text
        // shows targets once that write lands.
        let deadline = Date().addingTimeInterval(2)
        while (try? E2E.store.load(item.id).document.targets.isEmpty) != false, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        let targets = try E2E.store.load(item.id).document.targets
        XCTAssertFalse(targets.isEmpty, "a whole display has some text: the menu bar at least")
        print("E2E: timing return to targets ready on a \(item.size.width)x\(item.size.height) capture "
              + "\(LiveCapture.ms(targetsAt - start)) (\(targets.count) targets)")
    }

    func testEscapeCancels() async throws {
        let known = before
        let pasteboard = NSPasteboard.general
        let changeCount = pasteboard.changeCount
        try await LiveCapture.start(.captureAndEdit)
        let panel = try LiveCapture.panel(on: LiveCapture.screenUnderPointer)
        LiveCapture.key(Events.escape, in: panel)
        await E2E.wait("the overlay to close") { !LiveCapture.overlay.isActive }
        await E2E.settle(500)
        XCTAssertTrue(LiveCapture.newCaptures(since: known).isEmpty, "nothing saved")
        XCTAssertTrue(E2E.editors.windows.isEmpty, "no window")
        XCTAssertFalse(NSApp.windows.contains { $0.isVisible && $0.level == .normal }, "no window at all")
        XCTAssertEqual(pasteboard.changeCount, changeCount, "the clipboard is untouched")
    }

    // MARK: - Window pick

    func testSpacePicksAWindow() async throws {
        guard let (window, point) = LiveCapture.pickableWindow() else {
            throw XCTSkip("No other app's window is wholly on one display to pick")
        }
        let known = before
        try await LiveCapture.start(.captureToClipboard)
        let overlay = LiveCapture.overlay
        LiveCapture.key(0x31, in: try LiveCapture.panel(on: LiveCapture.screenUnderPointer))
        XCTAssertEqual(overlay.mode, .window, "Space switches to window picking")
        try LiveCapture.move(toCoreGraphics: point)
        let hovered = await E2E.wait("the window under the pointer") { overlay.hovered?.id == window.id }
        if !hovered {
            let other = overlay.hovered
            let inFrozen = overlay.frozen?.windows.firstIndex { $0.id == window.id }
            let picked = overlay.frozen.flatMap { frozen in frozen.windows.firstIndex { $0.id == other?.id } }
            print("E2E: window pick hovered \(other == nil ? "nothing" : "another window") (own \(other?.ownerPID == ProcessInfo.processInfo.processIdentifier), "
                  + "layer \(other?.layer ?? -1), z \(picked ?? -1)); target at z \(inFrozen ?? -1)")
        }
        try LiveCapture.click(atCoreGraphics: point)
        let (item, _) = try await LiveCapture.waitForCapture(since: known)
        let screen = NSScreen.screens.first { LiveCapture.coreGraphicsFrame(of: $0).contains(point) }
        let scale = Double(screen?.backingScaleFactor ?? 2)
        XCTAssertEqual(Double(item.size.width), window.frame.width * scale, accuracy: 2, "the window's size")
        XCTAssertEqual(Double(item.size.height), window.frame.height * scale, accuracy: 2)
        let source = try E2E.store.load(item.id).document.source
        XCTAssertEqual(source?.appName?.isEmpty, false, "the app name is recorded")
        if window.title?.isEmpty == false {
            XCTAssertNotNil(source?.windowTitle, "the window title is recorded")
        }
        print("E2E: window pick \(item.size.width)x\(item.size.height) px at \(scale)x; app name recorded "
              + "\(source?.appName != nil), title recorded \(source?.windowTitle != nil)")
    }

    // MARK: - Frozen at the hotkey (issue 72)

    /// The overlay shows a still of every display at its own pixel size, Exhibit A's own window is in it, and
    /// what changes after the hotkey is not: the window is gone before the drag, and the capture still holds it.
    func testTheStillHoldsOwnWindowsAndNothingAfterTheHotkey() async throws {
        let screen = LiveCapture.mainScreen
        let scale = Double(screen.backingScaleFactor)
        let window = LiveCapture.solidWindow(at: CGRect(x: screen.frame.minX + 200, y: screen.frame.minY + 200,
                                                        width: 400, height: 300))
        defer { window.orderOut(nil) }
        await E2E.settle(400)
        let known = before
        try await LiveCapture.start(.captureToClipboard)
        let frozen = try XCTUnwrap(LiveCapture.overlay.frozen)
        XCTAssertEqual(frozen.stills.count, NSScreen.screens.count, "a still of every display")
        for (index, shown) in NSScreen.screens.enumerated() {
            let still = try XCTUnwrap(frozen.still(for: try XCTUnwrap(shown.displayID)), "display \(index + 1)")
            XCTAssertEqual(Double(still.pixelSize.width), shown.frame.width * shown.backingScaleFactor, accuracy: 1)
            XCTAssertEqual(Double(still.pixelSize.height), shown.frame.height * shown.backingScaleFactor, accuracy: 1)
        }
        window.orderOut(nil)
        await E2E.settle(300)
        let panel = try LiveCapture.panel(on: screen)
        _ = LiveCapture.drag(on: panel, from: NSPoint(x: 220, y: 220), to: NSPoint(x: 580, y: 480))
        let (item, _) = try await LiveCapture.waitForCapture(since: known)
        let image = try E2E.store.load(item.id).original
        XCTAssertEqual(Double(image.width), 360 * scale, accuracy: 1, "the drag's size on its display")
        XCTAssertEqual(Double(image.height), 260 * scale, accuracy: 1)
        let solid = LiveCapture.solidFraction(image)
        XCTAssertGreaterThan(solid, 0.98, "Exhibit A's own window, as it was at the hotkey")
        print("E2E: frozen region of an own window closed after the hotkey: \(String(format: "%.3f", solid)) solid, "
              + "mean \(LiveCapture.meanColour(image))")
    }

    /// Space picks Exhibit A's own window too, cut out of the still at the window's frame.
    func testSpacePicksOwnWindowFromTheStill() async throws {
        let screen = LiveCapture.mainScreen
        let scale = Double(screen.backingScaleFactor)
        let frame = CGRect(x: screen.frame.minX + 240, y: screen.frame.minY + 160, width: 400, height: 300)
        let window = LiveCapture.solidWindow(at: frame)
        defer { window.orderOut(nil) }
        await E2E.settle(400)
        let known = before
        try await LiveCapture.start(.captureToClipboard)
        let overlay = LiveCapture.overlay
        LiveCapture.key(0x31, in: try LiveCapture.panel(on: LiveCapture.screenUnderPointer))
        let point = CGPoint(x: frame.midX, y: LiveCapture.mainDisplayHeight - frame.midY)
        try LiveCapture.move(toCoreGraphics: point)
        await E2E.wait("our window under the pointer") { overlay.hovered?.id == UInt32(window.windowNumber) }
        try LiveCapture.click(atCoreGraphics: point)
        let (item, _) = try await LiveCapture.waitForCapture(since: known)
        let image = try E2E.store.load(item.id).original
        XCTAssertEqual(Double(image.width), 400 * scale, accuracy: 1, "the window's size")
        XCTAssertEqual(Double(image.height), 300 * scale, accuracy: 1)
        let solid = LiveCapture.solidFraction(image)
        XCTAssertGreaterThan(solid, 0.98, "the window's own pixels")
        print("E2E: own window pick \(image.width)x\(image.height) px, \(String(format: "%.3f", solid)) solid, mean "
              + "\(LiveCapture.meanColour(image))")
    }

    /// The panel stays open through the hotkey, a click on the overlay and Esc, and closes once a capture is taken.
    func testThePanelStaysOpenUntilACaptureIsTaken() async throws {
        let statusItem = try XCTUnwrap(E2E.app.statusItem)
        statusItem.show()
        await E2E.wait("the panel") { statusItem.isShown }
        await E2E.settle(300)
        let panelWindow = statusItem.panelView?.window
        let wasKey = panelWindow?.isKeyWindow == true
        var known = before
        try await LiveCapture.start(.captureAndEdit)
        XCTAssertTrue(statusItem.isShown, "the hotkey leaves the panel open")
        let panel = try LiveCapture.panel(on: LiveCapture.screenUnderPointer)
        Events.click(at: NSPoint(x: 60, y: 60), in: panel)
        await E2E.settle(300)
        XCTAssertTrue(LiveCapture.overlay.isActive, "a click is not a selection")
        XCTAssertTrue(statusItem.isShown, "a click on the overlay leaves the panel open")
        LiveCapture.key(Events.escape, in: panel)
        await E2E.wait("the overlay to close") { !LiveCapture.overlay.isActive }
        await E2E.settle(400)
        XCTAssertTrue(statusItem.isShown, "Esc leaves the panel as it was")
        if wasKey {
            XCTAssertTrue(panelWindow?.isKeyWindow == true, "and gives it back the keys")
        }
        XCTAssertTrue(LiveCapture.newCaptures(since: known).isEmpty, "nothing saved")

        known = before
        try await LiveCapture.start(.captureToClipboard)
        LiveCapture.key(Events.returnKey, in: try LiveCapture.panel(on: LiveCapture.screenUnderPointer))
        _ = try await LiveCapture.waitForCapture(since: known)
        await E2E.wait("the panel to close") { !statusItem.isShown }
        print("E2E: panel open through the hotkey, a click and Esc; key given back \(wasKey ? "checked" : "n/a")")
    }

    // MARK: - Targets

    /// Background OCR finishes while the editor is open; its targets land through the document owner and the box
    /// drawn in the meantime survives.
    func testTargetsArriveWithoutLosingAMark() async throws {
        let known = before
        try await LiveCapture.start(.captureAndEdit)
        let panel = try LiveCapture.panel(on: LiveCapture.mainScreen)
        let up = LiveCapture.drag(on: panel, from: NSPoint(x: 160, y: 180), to: NSPoint(x: 760, y: 580))
        let (item, _) = try await LiveCapture.waitForCapture(since: known)
        let controller = try await LiveCapture.editor(for: item.id, keyTimeout: 0).controller
        let editor = controller.editor
        let loadedBeforeMark = editor.targetsLoaded
        // The box goes in as the canvas forwards a drag, in image pixels: the window may not be key (issue 53),
        // and a window that is not key gets no keys and swallows the first click.
        editor.choose(.box)
        editor.pointerDown(at: PixelPoint(x: 20, y: 20))
        editor.pointerDragged(to: PixelPoint(x: 120, y: 90))
        editor.pointerUp(at: PixelPoint(x: 200, y: 160))
        let marks = controller.editor.marks
        XCTAssertEqual(marks.count, 1, "the box is drawn")
        await E2E.wait("targets", timeout: 30) { controller.editor.targetsLoaded }
        let readyAt = ContinuousClock.now
        await E2E.settle(400)
        let saved = try E2E.store.load(item.id).document
        XCTAssertEqual(saved.marks, controller.editor.marks, "the box is on disk")
        XCTAssertEqual(saved.marks.map(\.id), marks.map(\.id), "and was not lost to the targets")
        XCTAssertEqual(saved.targets.count, controller.editor.document.targets.count, "the targets are on disk")
        print("E2E: timing mouse-up to targets ready \(LiveCapture.ms(readyAt - up)) (\(saved.targets.count) "
              + "targets; already read before the mark: \(loadedBeforeMark))")
    }

    // MARK: - Never capture

    /// Another app's window, listed for the test: blacked out in a whole-screen capture, refused as a pick.
    func testNeverCaptureBlacksOutAndRefuses() async throws {
        let screen = LiveCapture.screenUnderPointer
        guard let (window, point) = LiveCapture.pickableWindow(on: screen),
              let app = NSRunningApplication(processIdentifier: window.ownerPID),
              let bundleIdentifier = app.bundleIdentifier else {
            throw XCTSkip("No other app's window is wholly on the display under the pointer")
        }
        let policy = try XCTUnwrap(E2E.app.policy)
        let listed = NeverCaptureApp(name: app.localizedName ?? bundleIdentifier, bundleIdentifier: bundleIdentifier)
        let hadIt = policy.policy.neverCapture.contains(listed)
        policy.add(listed)
        defer { if !hadIt { policy.remove(listed) } }

        var known = before
        try await LiveCapture.start(.captureToClipboard)
        LiveCapture.key(Events.returnKey, in: try LiveCapture.panel(on: screen))
        let (item, _) = try await LiveCapture.waitForCapture(since: known)
        let image = try E2E.store.load(item.id).original
        let scale = Double(screen.backingScaleFactor)
        // Only the window's visible part is black (issue 75); near its centre it is frontmost. The label sits on
        // the centre line, so the patch is just above it.
        let display = LiveCapture.coreGraphicsFrame(of: screen)
        let local = PixelRect(x: (point.x - display.minX - 40) * scale, y: (point.y - display.minY - 65) * scale,
                              width: 80 * scale, height: 40 * scale)
        let black = LiveCapture.blackFraction(image, in: local)
        XCTAssertGreaterThan(black, 0.95, "the listed app's window is blacked out where it shows")
        print("E2E: never-capture window area \(String(format: "%.3f", black)) black")

        known = before
        try await LiveCapture.start(.captureToClipboard)
        LiveCapture.key(0x31, in: try LiveCapture.panel(on: screen))
        try LiveCapture.move(toCoreGraphics: point)
        await E2E.wait("the listed window under the pointer") { LiveCapture.overlay.hovered?.id == window.id }
        try LiveCapture.click(atCoreGraphics: point)
        await E2E.wait("the refusal") { E2E.model.captureRefusal != nil }
        XCTAssertFalse(LiveCapture.overlay.isActive)
        await E2E.wait("the panel saying why") { E2E.app.statusItem?.isShown == true }
        await E2E.settle(300)
        XCTAssertTrue(LiveCapture.newCaptures(since: known).isEmpty, "the pick was not captured")
    }

    /// Issue 75: a listed app's window with our window in front of its left part. Ours shows as it was; the
    /// rest of the listed window is black.
    func testNeverCaptureBehindAnotherWindowShowsTheFrontOne() async throws {
        let screen = LiveCapture.screenUnderPointer
        guard let (listedWindow, point) = LiveCapture.pickableWindow(on: screen),
              let app = NSRunningApplication(processIdentifier: listedWindow.ownerPID),
              let bundleIdentifier = app.bundleIdentifier else {
            throw XCTSkip("No other app's window is wholly on the display under the pointer")
        }
        let policy = try XCTUnwrap(E2E.app.policy)
        let listed = NeverCaptureApp(name: app.localizedName ?? bundleIdentifier, bundleIdentifier: bundleIdentifier)
        let hadIt = policy.policy.neverCapture.contains(listed)
        policy.add(listed)
        defer { if !hadIt { policy.remove(listed) } }

        // Ours covers the listed window from 20 points past its left edge to 10 points short of its centre.
        // Inside the visible frame, so the menu bar and the Dock, which sit above it, never cover it.
        let display = LiveCapture.coreGraphicsFrame(of: screen)
        let usable = CGRect(x: screen.visibleFrame.minX, y: LiveCapture.mainDisplayHeight - screen.visibleFrame.maxY,
                            width: screen.visibleFrame.width, height: screen.visibleFrame.height)
        let front = CGRect(x: listedWindow.frame.minX - 20, y: listedWindow.frame.minY - 20,
                           width: listedWindow.frame.width / 2 + 10, height: listedWindow.frame.height + 40)
            .intersection(usable)
        let window = LiveCapture.solidWindow(at: SelectionGeometry.cocoaRect(fromCoreGraphics: front,
                                                                             mainDisplayHeight: LiveCapture.mainDisplayHeight))
        defer { window.orderOut(nil) }
        await E2E.settle(400)

        let known = before
        try await LiveCapture.start(.captureToClipboard)
        LiveCapture.key(Events.returnKey, in: try LiveCapture.panel(on: screen))
        let (item, _) = try await LiveCapture.waitForCapture(since: known)
        let image = try E2E.store.load(item.id).original
        let scale = Double(screen.backingScaleFactor)
        let ours = CGRect(x: (front.minX - display.minX + 6) * scale, y: (front.minY - display.minY + 6) * scale,
                          width: (front.width - 12) * scale, height: (front.height - 12) * scale)
        let solid = LiveCapture.solidFraction(try XCTUnwrap(image.cropping(to: ours)))
        XCTAssertGreaterThan(solid, 0.98, "our window in front of the listed one shows as it was")
        // Just right of the centre and above the label's line.
        let uncovered = PixelRect(x: (point.x - display.minX + 10) * scale, y: (point.y - display.minY - 65) * scale,
                                  width: 40 * scale, height: 40 * scale)
        let black = LiveCapture.blackFraction(image, in: uncovered)
        XCTAssertGreaterThan(black, 0.95, "the uncovered part of the listed window is black")
        print("E2E: never-capture window behind ours: ours \(String(format: "%.3f", solid)) solid, uncovered part "
              + "\(String(format: "%.3f", black)) black")

        // An agent's capture leaves Exhibit A's windows out, so ours covers nothing there: black under it too.
        let number = try XCTUnwrap(NSScreen.screens.firstIndex(of: screen)) + 1
        let result = try await E2E.exhibit(["capture", "--display", String(number)])
        XCTAssertEqual(result.status, 0, LiveCapture.summary(result))
        let path = try XCTUnwrap(result.json["image"] as? String)
        let agent = try PNG.decode(Data(contentsOf: URL(fileURLWithPath: path)))
        // Other never-capture apps may show too; ours is named, and no app twice. Names are never printed.
        let named = try XCTUnwrap(result.json["blackedOut"] as? [String])
        XCTAssertFalse(named.isEmpty, "the listed app is named")
        XCTAssertEqual(Set(named).count, named.count, "each app once")
        let underOurs = PixelRect(x: (listedWindow.frame.minX - display.minX + 10) * scale,
                                  y: (point.y - display.minY - 65) * scale, width: 40 * scale, height: 40 * scale)
        let agentBlack = LiveCapture.blackFraction(agent, in: underOurs)
        XCTAssertGreaterThan(agentBlack, 0.95, "in an agent's capture the part under our window is black")
        print("E2E: agent capture, listed window under our window \(String(format: "%.3f", agentBlack)) black")
    }

    // MARK: - The bridge

    func testBridgeCapturesWithoutTakingFocus() async throws {
        let statusItem = try XCTUnwrap(E2E.app.statusItem)
        let visible = LiveCapture.visibleWindows()
        let key = NSApp.keyWindow
        let flashes = statusItem.flashes
        let main = LiveCapture.mainScreen
        let scale = Double(main.backingScaleFactor)

        let screenResult = try await E2E.exhibit(["capture", "--screen"])
        XCTAssertEqual(screenResult.status, 0, LiveCapture.summary(screenResult))
        try checkAgentCapture(screenResult, width: main.frame.width * scale, height: main.frame.height * scale)
        let regionResult = try await E2E.exhibit(["capture", "--region", "100,100,400,300"])
        XCTAssertEqual(regionResult.status, 0, LiveCapture.summary(regionResult))
        let id = try checkAgentCapture(regionResult, width: 400 * scale, height: 300 * scale)

        await E2E.wait("the glyph to blink for each") { statusItem.flashes == flashes + 2 }
        XCTAssertEqual(LiveCapture.visibleWindows(), visible, "no window appeared")
        XCTAssertTrue(NSApp.keyWindow === key, "the key window did not change")
        XCTAssertFalse(LiveCapture.overlay.isActive, "no overlay")

        let emails = try E2E.store.load(id).document.targets.filter { $0.kind == .email }.count
        let blur = try await E2E.exhibit(["blur", id.uuidString, "--kind", "email", "--allow-missing"])
        if emails > 0 {
            XCTAssertEqual(blur.status, 0, LiveCapture.summary(blur))
            let output = try XCTUnwrap(blur.json["output"] as? String)
            XCTAssertTrue(output.hasPrefix(E2E.seam.supportDirectory.path), "the export stays in the support folder")
        } else {
            // One selector that matched nothing fails even with --allow-missing (docs/cli.md).
            XCTAssertEqual(LiveCapture.summary(blur), "exit 3 code no_match")
        }
        print("E2E: bridge blur --kind email on a capture with \(emails) emails: \(LiveCapture.summary(blur))")
    }

    /// One `exhibit capture` result: exit 0, an id and PNG in the support directory, tagged agent, the right size,
    /// and no bundle path once anything was blurred.
    @discardableResult
    private func checkAgentCapture(_ result: E2E.CLIResult, width: Double, height: Double) throws -> UUID {
        let json = result.json
        let id = try XCTUnwrap((json["id"] as? String).flatMap(UUID.init(uuidString:)), "an id")
        let image = try XCTUnwrap(json["image"] as? String, "a PNG path")
        XCTAssertTrue(image.hasPrefix(E2E.seam.supportDirectory.path), "in the temporary support directory")
        let png = try PNG.decode(Data(contentsOf: URL(fileURLWithPath: image)))
        XCTAssertEqual(Double(png.width), width, accuracy: 1)
        XCTAssertEqual(Double(png.height), height, accuracy: 1)
        XCTAssertEqual(json["capturedBy"] as? String, "agent")
        let document = try E2E.store.load(id).document
        XCTAssertEqual(document.source?.capturedBy, .agent, "tagged agent in history")
        let autoBlur = try XCTUnwrap(json["autoBlur"] as? [String: Any])
        let blurred = autoBlur["blurred"] as? Int ?? 0
        XCTAssertEqual(autoBlur["enabled"] as? Bool, true, "auto-blur is on by default")
        if blurred > 0 {
            XCTAssertNil(json["bundle"], "no bundle path once something was blurred")
        } else {
            XCTAssertNotNil(json["bundle"])
        }
        print("E2E: bridge capture \(png.width)x\(png.height) px, \(json["targets"] as? Int ?? -1) targets, "
              + "\(blurred) blurred, bundle path given \(json["bundle"] != nil)")
        return id
    }

    // MARK: - Colour

    /// Recorded, not asserted (`docs/product/unit4-live-checklist.md`, issue 17): the colour space ScreenCaptureKit
    /// hands back on this display, and what the saved original and an export carry.
    func testRecordsTheColourSpace() async throws {
        let screen = LiveCapture.mainScreen
        let display = try XCTUnwrap(screen.displayID)
        let geometry = DisplayGeometry(id: display, frame: screen.frame, scale: screen.backingScaleFactor)
        let local = CGRect(x: 100, y: 100, width: 400, height: 300)
        let region = try XCTUnwrap(SelectionGeometry.region(local: local, on: geometry))
        let captured = try await ScreenCapturer.capture(region, policy: CapturePolicy())
        let saved = try PNG.decode(try PNG.encode(captured.image))
        let exported = try PNG.decode(try Renderer.renderPNG(original: saved, marks: [], scale: captured.scale))
        func name(_ image: CGImage) -> String {
            guard let space = image.colorSpace else { return "none" }
            let named = (space.name as String?).map { $0.replacingOccurrences(of: "kCGColorSpace", with: "") }
            let icc = (space.copyICCData() as Data?)?.count ?? 0
            let render = RenderColorSpace.of(image)
            let renders = render.map { $0 === space || $0 == space } == true ? "its own space" : "sRGB"
            return "\(named ?? "unnamed ICC") (wide gamut \(space.isWideGamutRGB), ICC \(icc) bytes, renders in "
                + "\(renders))"
        }
        let shown = screen.colorSpace?.localizedName ?? "unknown"
        print("E2E: colour display \(shown); live capture \(name(captured.image)); saved PNG \(name(saved)); "
              + "exported PNG \(name(exported))")
    }
}
