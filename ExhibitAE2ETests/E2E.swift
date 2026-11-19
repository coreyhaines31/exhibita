import AppKit
@testable import ExhibitA
import ExhibitCore
import ExhibitEditor
import ExhibitShell
import ExhibitStore
import XCTest

/// The running app, and the ways a test reaches into it: synthetic events posted to its own windows, waits that
/// keep the run loop turning, and offscreen pictures of its real windows. Nothing here needs a permission:
/// in-process events and a view's display cache are the app's own.
@MainActor
enum E2E {
    static var app: AppDelegate {
        guard let delegate = NSApp.delegate as? AppDelegate else { fatalError("Not hosted by Exhibit A") }
        return delegate
    }

    static var model: AppModel { app.model! }
    static var editors: EditorWindows { app.editors! }
    static var store: CaptureStore { model.store }

    static var seam: TestSeam.Configuration {
        guard let configuration = TestSeam.configuration else { fatalError("The test seam is off") }
        return configuration
    }

    // MARK: - Once per run

    private static var started = false
    private static var savedPasteboard: [NSPasteboardItem] = []

    /// Saves the clipboard before the first test and restores it after the last, and refuses to run anywhere but
    /// on the throwaway support directory.
    static func begin() throws {
        guard !started else { return }
        started = true
        let real = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Exhibit A").standardizedFileURL.path
        guard TestSeam.isActive, !store.directory.standardizedFileURL.path.hasPrefix(real) else {
            throw XCTSkip("Refusing to run: the app is not on its temporary support directory")
        }
        savedPasteboard = copyPasteboard()
        XCTestObservationCenter.shared.addTestObserver(Finisher())
    }

    private final class Finisher: NSObject, XCTestObservation {
        func testBundleDidFinish(_ testBundle: Bundle) {
            MainActor.assumeIsolated { E2E.finish() }
        }
    }

    static func finish() {
        closeEverything()
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if !savedPasteboard.isEmpty { pasteboard.writeObjects(savedPasteboard) }
    }

    private static func copyPasteboard() -> [NSPasteboardItem] {
        (NSPasteboard.general.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) { copy.setData(data, forType: type) }
            }
            return copy
        }
    }

    /// Closes every editor window and the panel, and waits for their documents to be written.
    static func closeEverything() {
        for controller in editors.windows.values {
            if let sheet = controller.window?.attachedSheet { controller.window?.endSheet(sheet, returnCode: .cancel) }
            controller.window?.close()
        }
        app.statusItem?.close()
        editors.flushAll()
    }

    // MARK: - Waiting

    /// Lets the run loop turn (SwiftUI updates, background renders, debounced writes) until `condition` holds.
    @discardableResult
    static func wait(_ what: String, timeout: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line,
                     until condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline {
                XCTFail("Timed out waiting for \(what)", file: file, line: line)
                return false
            }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return true
    }

    static func settle(_ milliseconds: Int = 120) async {
        try? await Task.sleep(for: .milliseconds(milliseconds))
    }

    // MARK: - Captures

    /// A capture taken through the same path as capture and edit, minus ScreenCaptureKit: saved to history,
    /// "reading text" set, the editor opened, the real `TargetFinder` run in the background. Returns its window once
    /// its targets are in.
    static func captureAndEdit(_ image: CGImage, scale: Double, appName: String = "Safari",
                               windowTitle: String = "Billing") async throws -> EditorWindowController {
        let before = Set(editors.windows.keys)
        let captured = CapturedImage(image: image, scale: scale, appName: appName, windowTitle: windowTitle,
                                     displayID: nil)
        await app.capture!.save(captured, action: .captureAndEdit)
        await wait("the editor to open") { editors.windows.keys.contains { !before.contains($0) } }
        let id = try XCTUnwrap(editors.windows.keys.first { !before.contains($0) })
        let controller = try XCTUnwrap(editors.windows[id])
        await wait("text to be read", timeout: 30) { controller.editor.targetsLoaded }
        await wait("the window to be key") { controller.window?.isKeyWindow == true }
        return controller
    }

    /// A capture saved to history with its targets already found, as an earlier session would have left it.
    static func seed(_ image: CGImage, scale: Double, appName: String, createdAt: Date = Date(),
                     targets: [Target]) throws -> UUID {
        let item = try store.create(image: image, scale: scale, capturedBy: .person, appName: appName, now: createdAt)
        var document = try store.load(item.id).document
        document.targets = targets
        try store.save(document)
        return item.id
    }

    // MARK: - Pictures

    /// The view as AppKit draws it, from its own display cache: never a screen capture.
    @discardableResult
    static func picture(_ view: NSView, named name: String) throws -> URL {
        view.layoutSubtreeIfNeeded()
        let bounds = view.bounds
        let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: bounds))
        view.cacheDisplay(in: bounds, to: rep)
        let data = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        let url = samplesDirectory.appendingPathComponent("\(name).png")
        try FileManager.default.createDirectory(at: samplesDirectory, withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        return url
    }

    static var samplesDirectory: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("docs/samples/e2e", isDirectory: true)
    }
}
