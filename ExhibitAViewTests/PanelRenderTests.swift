import AppKit
import CoreGraphics
import ExhibitCore
import ExhibitEditor
import ExhibitInterpret
import ExhibitShell
import ExhibitStore
import PanelKit
import SwiftUI
import XCTest

/// Renders the panel and Settings on fixture data to PNGs for a visual check, with `ImageRenderer` and an
/// unattached hosting view: no window is created or shown, and Exhibit A itself is never launched. History
/// lives in a temporary folder and preferences in a throwaway defaults suite.
///
/// `EXHIBIT_RENDER_DIR=<folder>` writes the PNGs there; the repo keeps them in `docs/samples/app`.
@MainActor
final class PanelRenderTests: XCTestCase {
    private var suiteName = ""
    private var captures: URL?

    /// Wednesday 2026-11-18, 3:41 PM local time.
    private let now: Date = {
        var components = DateComponents(year: 2026, month: 11, day: 18, hour: 15, minute: 41)
        components.calendar = Calendar.current
        return components.date ?? Date()
    }()
    private let day: TimeInterval = 86_400

    override func setUp() async throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        PanelFont.register()
        suiteName = "com.exhibitaformac.tests.\(UUID().uuidString)"
        Preferences.defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        captures = FileManager.default.temporaryDirectory.appendingPathComponent(suiteName)
            .appendingPathComponent("Captures")
    }

    override func tearDown() async throws {
        Preferences.defaults.removePersistentDomain(forName: suiteName)
        Preferences.defaults = .standard
        if let captures { try? FileManager.default.removeItem(at: captures.deletingLastPathComponent()) }
    }

    private func makeModel(permission: ScreenRecordingState = .granted,
                           system: SystemScreenshotShortcuts = .factory) throws -> AppModel {
        let model = AppModel(store: CaptureStore(directory: try XCTUnwrap(captures)), permission: permission,
                             system: system, launchesAtLogin: true)
        model.clock = { [now] in now }
        return model
    }

    /// Four captures through the real store: two today (one by an agent), one yesterday, one near the sweep.
    private func fillHistory(_ model: AppModel) async throws {
        let store = model.store
        try store.create(image: FixtureShots.browser(), scale: 2, capturedBy: .person, appName: "Safari",
                         windowTitle: "Billing", now: now.addingTimeInterval(-12 * 60))
        try store.create(image: FixtureShots.terminal(), scale: 2, capturedBy: .agent, now: now.addingTimeInterval(-3 * 60))
        try store.create(image: FixtureShots.document(), scale: 1, capturedBy: .person, appName: "Notes",
                         now: now.addingTimeInterval(-day - 2 * 3600))
        try store.create(image: FixtureShots.browser(dark: true), scale: 2, capturedBy: .person, appName: "Linear",
                         now: now.addingTimeInterval(-28 * day))
        await model.reload()
        XCTAssertEqual(model.items.count, 4)
        XCTAssertEqual(model.thumbnails.count, 4)
    }

    // MARK: - Checks on the model behind the views

    func testHistoryReadsThroughTheStoreNewestFirst() async throws {
        let model = try makeModel()
        try await fillHistory(model)
        XCTAssertEqual(model.content, .history)
        XCTAssertEqual(model.rows.map(\.title), ["Capture", "Safari", "Notes", "Linear"])
        XCTAssertEqual(model.rows.first?.tag, "by agent")
        XCTAssertEqual(model.rows.last?.expiry, "Deleted in 2 days")
        XCTAssertEqual(model.summary, "4 captures, kept 30 days")
    }

    func testRetentionChangeSweepsOnReload() async throws {
        let model = try makeModel()
        try await fillHistory(model)
        model.setRetention(.days(7))
        XCTAssertEqual(Preferences.retention, .days(7))
        await model.reload()
        XCTAssertEqual(model.items.map(\.appName), [nil, "Safari", "Notes"])
    }

    func testPurgeEmptiesHistory() async throws {
        let model = try makeModel()
        try await fillHistory(model)
        model.selected = model.items.first?.id
        await model.purgeAll()
        XCTAssertEqual(model.content, .empty)
        XCTAssertNil(model.selected)
        XCTAssertTrue(model.thumbnails.isEmpty)
    }

    func testRefusedHotkeyKeepsTheBindingAndSaysWhy() throws {
        let model = try makeModel()
        var applied: [HotkeyBindings] = []
        model.onBindingsChanged = { applied.append($0) }
        model.record(KeyCombo(keyCode: KeyCombo.digit4, modifiers: [.command, .shift]), for: .captureAndEdit)
        XCTAssertEqual(model.bindings.combo(for: .captureAndEdit).display, "⌥⇧4")
        XCTAssertEqual(model.message(for: .captureAndEdit), HotkeyIssue.takenBySystem(.saveSelection).message)
        XCTAssertEqual(applied.count, 1, "the recorder is reset to the key in effect")

        model.record(KeyCombo(keyCode: 0x08, modifiers: [.control, .option]), for: .captureAndEdit)
        XCTAssertNil(model.message(for: .captureAndEdit))
        XCTAssertEqual(Preferences.customHotkeys[.captureAndEdit]?.display, "⌃⌥C")
        model.record(nil, for: .captureAndEdit)
        XCTAssertTrue(Preferences.customHotkeys.isEmpty)
    }

    func testDefaultsMoveAfterTakeover() throws {
        let model = try makeModel()
        var applied: [HotkeyBindings] = []
        model.onBindingsChanged = { applied.append($0) }
        model.updateSystemShortcuts(.factory)
        XCTAssertTrue(applied.isEmpty, "no change, nothing re-registered")
        model.updateSystemShortcuts(Self.takenOver)
        XCTAssertEqual(applied.last?.combo(for: .captureAndEdit).display, "⇧⌘4")
        XCTAssertEqual(model.emptyHint, "Press ⇧⌘4 to capture and mark up, or ⌃⇧⌘4 to copy a capture.")
    }

    func testRefusedWindowPickSaysWhyUntilDismissed() throws {
        let model = try makeModel()
        XCTAssertNil(model.captureRefusal)
        let entry = try XCTUnwrap(CapturePolicy.defaultNeverCapture.first)
        guard case .blackOut(let reason) = CapturePolicy().decision(
            for: CaptureSubject(bundleIdentifier: entry.bundleIdentifier, appName: entry.name)) else {
            return XCTFail("the default list refuses \(entry.name)")
        }
        model.refuseCapture(reason: reason)
        XCTAssertEqual(model.captureRefusal, "\(entry.name) is on the never-capture list, so its window was not "
                       + "captured. Change the list in Settings, Privacy.")
        model.clearCaptureRefusal()
        XCTAssertNil(model.captureRefusal)
    }

    /// A released build's updater, so the panel shows the version and Check for Updates.
    static let updates = UpdateSettings(isConfigured: true, version: "0.1.2", checksAutomatically: true)

    static let takenOver = SystemScreenshotShortcuts(symbolicHotKeys: [
        "30": ["enabled": false], "31": ["enabled": false]
    ] as [String: Any])

    // MARK: - Renders

    func testRendersThePanel() async throws {
        let empty = try makeModel()
        await empty.reload()
        try renderPanel(empty, name: "panel-empty")

        let permission = try makeModel(permission: .notAsked)
        await permission.reload()
        try renderPanel(permission, name: "panel-permission")

        let denied = try makeModel(permission: .denied)
        await denied.reload()
        try renderPanel(denied, name: "panel-permission-denied", schemes: [.light])

        let history = try makeModel(system: Self.takenOver)
        try await fillHistory(history)
        history.selected = history.items.dropFirst().first?.id
        try renderPanel(history, name: "panel-history")

        history.refuseCapture(reason: "1Password is on the never-capture list")
        try renderPanel(history, name: "panel-refused")
    }

    func testRendersSettings() async throws {
        let model = try makeModel()
        try await fillHistory(model)
        model.record(KeyCombo(keyCode: 0x08, modifiers: [.control, .option]), for: .captureToClipboard)
        model.record(KeyCombo(keyCode: KeyCombo.digit4, modifiers: [.command, .shift]), for: .captureAndEdit)
        try renderSettings(model, name: "settings", policy: CapturePolicyModel(file: nil))

        let after = try makeModel(permission: .denied, system: Self.takenOver)
        try renderSettings(after, name: "settings-taken-over", schemes: [.light])
    }

    func testRendersShortcutSettings() throws {
        let model = try makeModel()
        model.recordShortcut(.character("q"), modifiers: [], for: .tool(.arrow))
        model.recordShortcut(.character("k"), modifiers: [.shift], for: .blurAllSensitive)
        model.recordShortcut(.character("c"), modifiers: [], for: .tool(.highlight))
        try renderForm(name: "settings-shortcuts") {
            HotkeysSection(model: model, actions: SettingsActions(), drawsRecorders: false)
            ShortcutsSection(model: model)
        }
    }

    /// Each state of "Instructions in your own words", on its own: the default in use with no click, no server,
    /// a server with no models, a chosen model no longer installed, and Other.
    func testRendersFreeFormSettings() throws {
        let ollama = URL(string: "http://127.0.0.1:11434")!
        let lmStudio = URL(string: "http://127.0.0.1:1234/v1")!
        let installed = Discovery(probes: [
            .found(ModelServer(kind: .ollama, url: ollama, models: ["ornith-1.5:9b", "qwen3.8:27b"])),
            .notRunning(.openAICompatible, lmStudio)
        ])
        let nothing = Discovery(probes: [.notRunning(.ollama, ollama), .notRunning(.openAICompatible, lmStudio)])
        let empty = Discovery(probes: [.noModels(ModelServer(kind: .ollama, url: ollama, models: [])),
                                       .notRunning(.openAICompatible, lmStudio)])
        let states: [(String, FreeFormSettings)] = [
            ("settings-free-form", FreeFormSettings(settings: ModelSettings(), discovery: installed)),
            ("settings-free-form-no-server", FreeFormSettings(settings: ModelSettings(), discovery: nothing)),
            ("settings-free-form-no-models", FreeFormSettings(settings: ModelSettings(), discovery: empty)),
            ("settings-free-form-missing", FreeFormSettings(
                settings: ModelSettings(choice: .installed(server: .ollama, url: ollama.absoluteString,
                                                           model: "llama3.2:3b")), discovery: installed)),
            ("settings-free-form-other", FreeFormSettings(
                settings: ModelSettings(endpoint: "http://127.0.0.1:8080/v1", model: "my-model", choice: .other),
                discovery: installed))
        ]
        for (name, settings) in states {
            try renderForm(name: name) { FreeFormSection(model: settings) }
        }
    }

    /// The command line row unlinked and the updater configured. The fake app bundle sits at a fixed /tmp path so
    /// the MCP line in the sample is the same on every Mac.
    func testRendersCommandLineAndUpdateSettings() throws {
        let model = try makeModel()
        let macOS = URL(fileURLWithPath: "/tmp/exhibita-render/Exhibit A.app/Contents/MacOS")
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        let bundled = macOS.appendingPathComponent("exhibit").path
        FileManager.default.createFile(atPath: bundled, contents: Data())
        let tool = CommandLineTool(bundled: bundled, directories: [], userDirectory: "/nonexistent")
        XCTAssertEqual(tool.state, .notLinked)
        let updates = UpdateSettings(isConfigured: true, version: "0.1.0", checksAutomatically: true)
        try renderSettings(model, name: "settings-command-line", updates: updates, commandLine: tool)
        try? FileManager.default.removeItem(atPath: "/tmp/exhibita-render")
    }

    // MARK: - Rendering

    private func renderFolder() -> URL {
        let path = ProcessInfo.processInfo.environment["EXHIBIT_RENDER_DIR"]
        let folder = path.map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("exhibita-renders")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// PanelKit's own path: `ImageRenderer` over a backdrop, no window.
    private func renderPanel(_ model: AppModel, name: String, schemes: [ColorScheme] = [.light, .dark]) throws {
        for scheme in schemes {
            let view = PanelView(model: model, actions: PanelActions(), updates: Self.updates)
                .padding(24)
                .background(scheme == .dark ? Color(white: 0.05) : Color(white: 0.8))
                .environment(\.colorScheme, scheme)
                .environment(\.panelSnapshot, true)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.cgImage, name)
            try write(image, to: "\(name)-\(scheme == .dark ? "dark" : "light")")
        }
    }

    /// Settings is a native form, whose controls `ImageRenderer` can't draw, so it goes through an unattached
    /// hosting view's display cache instead. Still no window.
    private func renderSettings(_ model: AppModel, name: String, schemes: [ColorScheme] = [.light, .dark],
                                policy: CapturePolicyModel? = nil,
                                freeForm: FreeFormSettings = FreeFormSettings(settings: ModelSettings()),
                                updates: UpdateSettings = UpdateSettings(version: "0.1.0"),
                                commandLine: CommandLineTool = CommandLineTool(bundled: nil, directories: [],
                                                                               userDirectory: "/nonexistent")) throws {
        for scheme in schemes {
            let hosting = NSHostingView(rootView: SettingsView(model: model, actions: SettingsActions(),
                                                               drawsRecorders: false, policy: policy,
                                                               freeForm: freeForm, updates: updates,
                                                               commandLine: commandLine)
                .background(Color(nsColor: .windowBackgroundColor)))
            hosting.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
            hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
            hosting.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.3))
            let rep = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds), name)
            hosting.cacheDisplay(in: hosting.bounds, to: rep)
            let image = try XCTUnwrap(rep.cgImage, name)
            try write(image, to: "\(name)-\(scheme == .dark ? "dark" : "light")")
        }
    }

    /// A few Settings sections on their own, the same way as `renderSettings`.
    private func renderForm<Content: View>(name: String, schemes: [ColorScheme] = [.light, .dark],
                                           @ViewBuilder content: () -> Content) throws {
        let form = Form(content: content).formStyle(.grouped).frame(width: SettingsView.width)
            .fixedSize(horizontal: false, vertical: true)
        for scheme in schemes {
            let hosting = NSHostingView(rootView: form.background(Color(nsColor: .windowBackgroundColor)))
            hosting.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
            hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
            hosting.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.3))
            let rep = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds), name)
            hosting.cacheDisplay(in: hosting.bounds, to: rep)
            let image = try XCTUnwrap(rep.cgImage, name)
            try write(image, to: "\(name)-\(scheme == .dark ? "dark" : "light")")
        }
    }

    private func write(_ image: CGImage, to name: String) throws {
        let url = renderFolder().appendingPathComponent("\(name).png")
        let data = try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
        try data.write(to: url)
        print("Rendered \(url.path)")
    }
}

extension PanelRenderTests {
    /// The window's view, at the height the window takes on a laptop screen: the form scrolls inside it instead of
    /// making the window taller than the screen.
    func testSettingsFitTheScreen() throws {
        XCTAssertEqual(SettingsView.windowHeight(onScreenOfHeight: 848), 720)
        XCTAssertEqual(SettingsView.windowHeight(onScreenOfHeight: 600), 520)
        XCTAssertEqual(SettingsView.windowHeight(onScreenOfHeight: 300), SettingsView.minimumWindowHeight)
        XCTAssertEqual(SettingsView.windowHeight(onScreenOfHeight: nil), SettingsView.preferredWindowHeight)

        let model = try makeModel()
        let size = NSSize(width: SettingsView.width, height: SettingsView.windowHeight(onScreenOfHeight: 600))
        let hosting = NSHostingView(rootView: SettingsView(model: model, actions: SettingsActions(),
                                                           drawsRecorders: false, fitsContent: false)
            .background(Color(nsColor: .windowBackgroundColor)))
        hosting.sizingOptions = []
        hosting.appearance = NSAppearance(named: .aqua)
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        XCTAssertEqual(hosting.frame.size, size, "the form does not force the window taller")
        let rep = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        try write(try XCTUnwrap(rep.cgImage), to: "settings-window-light")
    }
}
