import AppKit
import ExhibitCore
import ExhibitEditor
import ExhibitShell
import ExhibitStore
import os
import SwiftUI
import UniformTypeIdentifiers

/// Opens and closes editor windows, one per capture, and carries out what only the app can do: the
/// clipboard, files, closing. The editor window is the one place Exhibit A activates and takes key focus,
/// because a person just asked for it.
@MainActor
final class EditorWindows {
    private nonisolated static let logger = Logger(subsystem: Brand.bundleIdentifier, category: "Editor")

    private let model: AppModel
    let captures: OpenCaptures
    private(set) var windows: [UUID: EditorWindowController] = [:]
    /// Runs before an editor opens, e.g. to close the panel.
    var willOpen: () -> Void = {}
    /// Opens Settings, for the "needs a model" link.
    var openSettings: () -> Void = {}

    init(model: AppModel, captures: OpenCaptures) {
        self.model = model
        self.captures = captures
    }

    /// Opens a capture just taken, with its image already in memory, centred on `screen`.
    func open(document: CaptureDocument, original: CGImage, on screen: NSScreen?) {
        let capture = captures.open(document: document, original: original)
        present(capture, on: screen)
    }

    /// Opens a capture from history.
    func open(_ id: UUID) {
        if let existing = windows[id] {
            willOpen()
            existing.focus()
            return
        }
        Task {
            do {
                let capture = try await captures.open(id)
                present(capture, on: NSScreen.main)
            } catch {
                Self.logger.error("Opening a capture failed: \(error.localizedDescription)")
                NSSound.beep()
            }
        }
    }

    /// Keys changed in Settings reach editors already open.
    func apply(_ keymap: EditorKeymap) {
        for controller in windows.values { controller.editor.keymap = keymap }
    }

    /// Writes every open capture's pending marks; for quitting.
    func flushAll() {
        captures.flushAll()
    }

    private func present(_ capture: OpenCapture, on screen: NSScreen?) {
        willOpen()
        let id = capture.owner.id
        if let existing = windows[id] {
            existing.focus()
            return
        }
        let controller = EditorWindowController(capture: capture, screen: screen ?? NSScreen.main,
                                                exportsFolder: Self.exportsFolder)
        controller.editor.keymap = model.keymap
        controller.onClose = { [weak self] exported in self?.closed(id, exported: exported) }
        controller.openSettings = { [weak self] in self?.openSettings() }
        windows[id] = controller
        controller.focus()
    }

    private func closed(_ id: UUID, exported: Bool) {
        windows[id] = nil
        captures.close(id)
        let store = model.store
        let policy = model.retention
        Task {
            if exported {
                // "Until exported" deletes the capture now; other policies keep it.
                _ = await Task.detached { try? store.didExport(id, policy: policy) }.value
            }
            await model.reload()
        }
    }

    /// Where ⇧⌘C writes the file whose path it copies. Temporary: the capture itself stays in history.
    static var exportsFolder: URL {
        TestSeam.exportsFolder
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("Exhibit A Exports", isDirectory: true)
    }
}

/// One editor window: the SwiftUI editor in a window whose title bar sits over the metal toolbar. Keys go
/// to the editor before anything else.
@MainActor
final class EditorWindowController: NSObject, NSWindowDelegate {
    private nonisolated static let logger = Logger(subsystem: Brand.bundleIdentifier, category: "Editor")

    let editor: CaptureEditor
    /// Hold D or press / to say or type what to change.
    let dictation: DictationSession
    private let capture: OpenCapture
    let canvas: EditorCanvasModel
    private let exportsFolder: URL
    private(set) var window: EditorWindow?
    private var exported = false
    var onClose: (Bool) -> Void = { _ in }
    var openSettings: () -> Void = {}
    /// Makes each editor's transcriber. The end-to-end tests swap in a fake so D never reaches the microphone.
    static var makeTranscriber: @MainActor () -> (any SpeechTranscribing)? = { SpeechTranscription.make() }

    init(capture: OpenCapture, screen: NSScreen?, exportsFolder: URL) {
        self.capture = capture
        self.exportsFolder = exportsFolder
        editor = CaptureEditor(owner: capture.owner)
        // Creating the transcriber touches neither the microphone nor permissions; the first hold of D does.
        dictation = DictationSession(editor: editor, original: capture.original,
                                     transcriber: Self.makeTranscriber(),
                                     model: { FreeFormSettings.shared.interpreter() })
        canvas = EditorCanvasModel(original: capture.original, scale: capture.owner.document.scale)
        super.init()
        // The first frame is already the renderer's output, so a reopened capture never flashes what its
        // blurs hide.
        canvas.renderNow(editor.marks)
        window = makeWindow(on: screen)
    }

    func focus() {
        guard let window else { return }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        // An LSUIElement app isn't active when a hotkey fires, and macOS 14's cooperative activate() can be
        // declined; a window that isn't key would spend the first keystroke becoming key. Insist once.
        DispatchQueue.main.async { [weak window] in
            guard let window, !window.isKeyWindow || !NSApp.isActive else { return }
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
    }

    private func makeWindow(on screen: NSScreen?) -> EditorWindow {
        let document = capture.owner.document
        let pixelSize = CGSize(width: capture.original.width, height: capture.original.height)
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let available = CGSize(width: visible.width * EditorLayout.screenShare,
                               height: visible.height * EditorLayout.screenShare)
        let pointsPerPixel = EditorLayout.pointsPerPixel(pixelSize: pixelSize, scale: document.scale,
                                                         available: available)
        editor.tolerance = 4 / pointsPerPixel
        let size = EditorLayout.contentSize(pixelSize: pixelSize, pointsPerPixel: pointsPerPixel)

        let window = EditorWindow(contentRect: NSRect(origin: .zero, size: size),
                                  styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                                  backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.title = Self.title(for: document)
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = false
        window.delegate = self
        window.editor = editor
        window.dictation = dictation
        window.onAppCommand = { [weak self] in self?.perform($0) }
        let actions = EditorActions(copyAndClose: { [weak self] in self?.perform(.copyAndClose) },
                                    save: { [weak self] in self?.perform(.save) },
                                    copyPath: { [weak self] in self?.perform(.copyPath) },
                                    close: { [weak self] in self?.perform(.close) },
                                    openLink: { [weak self] in self?.open($0) })
        let view = EditorView(editor: editor, canvas: canvas, actions: actions, pointsPerPixel: pointsPerPixel,
                              dictation: dictation)
        let hosting = NSHostingView(rootView: view)
        // The window's size comes from `EditorLayout`, not from SwiftUI, whose sizing adds the title bar again.
        hosting.sizingOptions = []
        window.contentView = hosting
        // The content spans the whole frame, title bar included (the toolbar sits under it), so the frame is the
        // size. `setContentSize` would add a title bar's height on top.
        window.setFrame(NSRect(origin: .zero, size: size), display: false)
        // Centred on the display the capture came from.
        let frame = window.frame
        window.setFrameOrigin(NSPoint(x: visible.midX - frame.width / 2, y: visible.midY - frame.height / 2))
        return window
    }

    static func title(for document: CaptureDocument) -> String {
        [document.source?.appName, document.source?.windowTitle].compactMap { $0 }.joined(separator: ", ")
            .ifEmpty("Capture")
    }

    // MARK: - App commands

    private func perform(_ command: EditorCommand) {
        editor.perform(command)
        switch command {
        case .copyAndClose:
            guard let png = exportPNG() else { return }
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setData(png, forType: .png)
            exported = true
            editor.show("Copied")
            window?.close()
        case .save:
            save()
        case .copyPath:
            guard let png = exportPNG() else { return }
            do {
                let url = try EditorExport.write(png, named: EditorExport.fileName(for: editor.document),
                                                 in: exportsFolder)
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(url.path, forType: .string)
                exported = true
                editor.show("Path copied")
            } catch {
                fail("Writing the file failed", error)
            }
        case .close:
            window?.close()
        default:
            break
        }
    }

    private func save() {
        guard let window, let png = exportPNG() else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = EditorExport.fileName(for: editor.document)
        panel.canCreateDirectories = true
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            MainActor.assumeIsolated {
                do {
                    try png.write(to: url, options: .atomic)
                    self?.exported = true
                    self?.editor.show("Saved")
                } catch {
                    self?.fail("Saving failed", error)
                }
            }
        }
    }

    /// The flattened PNG: `Renderer` then `PNG.encode`, the same bytes the CLI writes.
    private func exportPNG() -> Data? {
        do {
            return try EditorExport.png(editor.document, original: capture.original)
        } catch {
            fail("Exporting failed", error)
            return nil
        }
    }

    private func open(_ link: DictationLink) {
        switch link {
        case .modelSettings: openSettings()
        case .microphoneSettings: SystemPrivacy.open(.microphone)
        case .speechSettings: SystemPrivacy.open(.speechRecognition)
        }
    }

    private func fail(_ message: String, _ error: Error) {
        Self.logger.error("\(message): \(error.localizedDescription)")
        editor.show(message)
        NSSound.beep()
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        dictation.close()
        editor.commitText()
        window?.editor = nil
        window?.dictation = nil
        onClose(exported)
    }

    /// Letting go of D in another window must not leave the microphone on.
    func windowDidResignKey(_ notification: Notification) {
        dictation.release()
    }
}

/// Routes keys to the editor first. Only keys the editor ignores reach AppKit.
final class EditorWindow: NSWindow {
    weak var editor: CaptureEditor?
    weak var dictation: DictationSession?
    var onAppCommand: (EditorCommand) -> Void = { _ in }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func keyDown(with event: NSEvent) {
        if !route(event) { super.keyDown(with: event) }
    }

    /// The dictate key (D unless changed) coming up stops listening.
    override func keyUp(with event: NSEvent) {
        if let key = EditorKey(event), editor?.keymap.releasesDictation(key) == true { dictation?.release() }
        super.keyUp(with: event)
    }

    /// ⌘ keys arrive here before `keyDown`; the editor's take precedence over the (absent) menus.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.type == .keyDown, event.modifierFlags.contains(.command), route(event) { return true }
        return super.performKeyEquivalent(with: event)
    }

    private func route(_ event: NSEvent) -> Bool {
        guard let editor, let key = EditorKey(event) else { return false }
        // Esc while listening cancels dictation instead of closing.
        if let dictation, dictation.intercept(key) { return true }
        let modifiers = KeyModifiers(event)
        let typed: EditorKey
        // Labels take what was typed, shifted letters and all; tool keys read the unmodified key.
        if editor.editingTextID != nil, case .character = key, let characters = event.characters, !characters.isEmpty,
           modifiers.isSubset(of: [.shift]) {
            typed = .character(characters)
        } else {
            typed = key
        }
        switch editor.handle(typed, modifiers: modifiers) {
        case .handled: return true
        case .app(.dictate):
            // Held keys repeat; only the first press starts listening.
            if !event.isARepeat { dictation?.press() }
            return true
        case .app(.typeInstruction):
            dictation?.beginTyping()
            return true
        case .app(let command):
            onAppCommand(command)
            return true
        case .ignored: return false
        }
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}
