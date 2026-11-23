import AppKit
import CoreGraphics
import ExhibitCore
import ExhibitEditor
import ExhibitShell
import ExhibitStore
import PanelKit
import SwiftUI
import XCTest

/// Renders the editor (toolbar, status strip and canvas) on a fixture capture to PNGs with `ImageRenderer`: no
/// window is created or shown and Exhibit A is never launched. Marks are made through the editor's own pointer
/// and key handling, the way a person would make them.
///
/// `EXHIBIT_RENDER_DIR=<folder>` writes the PNGs there; the repo keeps them in `docs/samples/app`.
@MainActor
final class EditorRenderTests: XCTestCase {
    private let fixture = EditorFixture()

    override func setUp() async throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        PanelFont.register()
    }

    private func makeEditor(targets: Bool = true) -> CaptureEditor {
        let writer = DocumentWriter(sink: DiscardingSink(), delay: 60)
        let owner = DocumentOwner(document: fixture.document(withTargets: targets), targetsLoaded: targets,
                                  writer: writer)
        return CaptureEditor(owner: owner)
    }

    // MARK: - Checks

    func testCanvasShowsWhatExports() throws {
        let editor = makeEditor()
        _ = editor.handle(.character("b"))
        editor.pointerDown(at: fixture.center("email"))
        editor.pointerUp(at: fixture.center("email"))
        XCTAssertEqual(editor.marks.first?.kind, .blur)
        let canvas = EditorCanvasModel(original: fixture.image, scale: EditorFixture.scale)
        canvas.renderNow(editor.marks)
        let shown = try PNG.encode(XCTUnwrap(canvas.rendered))
        XCTAssertEqual(shown, try EditorExport.png(editor.document, original: fixture.image))
    }

    /// The window's traffic lights take 74 points on the left, so the toolbar must fit the minimum width with that
    /// inset, also with long remapped keys (issue 70; renders pass no inset and would not show it).
    func testToolbarFitsTheMinimumWidthBesideTheTrafficLights() {
        let editor = makeEditor()
        for keymap in [EditorKeymap.standard, Self.longKeys] {
            editor.keymap = keymap
            let toolbar = NSHostingView(rootView: EditorToolbar(editor: editor, actions: EditorActions(),
                                                                leadingInset: 74))
            XCTAssertLessThanOrEqual(toolbar.fittingSize.width, EditorLayout.minimumWidth)
        }
    }

    /// Issue 109: the strip's Copy, Copy & close and Copy & delete reach their own actions.
    func testFinishingActionsReachTheirCommands() {
        var ran: [String] = []
        let actions = EditorActions(copy: { ran.append("copy") }, copyAndClose: { ran.append("close") },
                                    copyAndDelete: { ran.append("delete") }, save: { ran.append("save") },
                                    copyPath: { ran.append("path") }, close: { ran.append("esc") })
        for command in [EditorCommand.copy, .copyAndClose, .copyAndDelete, .save, .copyPath, .close] {
            actions.perform(command)
        }
        XCTAssertEqual(ran, ["copy", "close", "delete", "save", "path", "esc"])
    }

    private static let longKeys = EditorKeymap(custom: [
        .tool(.arrow): EditorShortcut("q", [.control, .option, .shift]),
        .tool(.highlight): EditorShortcut("j", [.command, .option]),
        .blurAllSensitive: EditorShortcut("k", [.control, .option, .shift]),
        .dictate: EditorShortcut(" "),
        .color(.red): EditorShortcut("8", [.control, .option])
    ])

    func testCaptureShowsOneToOneWhereItFitsAndScalesDownOtherwise() {
        let pixels = CGSize(width: 1240, height: 760)
        let roomy = EditorLayout.pointsPerPixel(pixelSize: pixels, scale: 2, available: CGSize(width: 1600, height: 1000))
        XCTAssertEqual(roomy, 0.5, "a 2x capture at its own points")
        let tight = EditorLayout.pointsPerPixel(pixelSize: pixels, scale: 2, available: CGSize(width: 500, height: 1000))
        XCTAssertLessThan(tight, 0.5)
        XCTAssertEqual(tight * pixels.width, 500 - 2 * EditorLayout.mountPadding, accuracy: 0.001)
        let size = EditorLayout.contentSize(pixelSize: CGSize(width: 200, height: 100), pointsPerPixel: 0.5)
        XCTAssertEqual(size.width, EditorLayout.minimumWidth, "small captures still fit the toolbar")
    }

    // MARK: - Renders

    func testRendersTheEditor() throws {
        // Hotkey, drag, B, click, A, drag, ↩: one email blurred and an arrow at the button, plus a step.
        let marked = makeEditor()
        _ = marked.handle(.character("b"))
        click(marked, fixture.center("email"))
        _ = marked.handle(.character("n"))
        click(marked, PixelPoint(x: 300, y: 330))
        _ = marked.handle(.character("a"))
        drag(marked, from: PixelPoint(x: 700, y: 520), to: fixture.center("update"))
        try render(marked, name: "editor-marked")

        // Straight after capture: no marks yet, the finder still reading, a blur being dragged by hand.
        let loading = makeEditor(targets: false)
        _ = loading.handle(.character("b"))
        loading.pointerDown(at: PixelPoint(x: 640, y: 350))
        loading.pointerDragged(to: PixelPoint(x: 1060, y: 400))
        try render(loading, name: "editor-reading-text", schemes: [.light])

        // Targets in, nothing covered: the quiet secrets count, and a label being typed.
        let secrets = makeEditor()
        _ = secrets.handle(.character("t"))
        click(secrets, PixelPoint(x: 820, y: 220))
        for letter in "Renews soon" { _ = secrets.handle(.character(String(letter))) }
        try render(secrets, name: "editor-secrets")
    }

    // MARK: - Rendering

    private func click(_ editor: CaptureEditor, _ point: PixelPoint) {
        editor.pointerDown(at: point)
        editor.pointerUp(at: point)
    }

    private func drag(_ editor: CaptureEditor, from start: PixelPoint, to end: PixelPoint) {
        editor.pointerDown(at: start)
        editor.pointerDragged(to: end)
        editor.pointerUp(at: end)
    }

    private func render(_ editor: CaptureEditor, name: String, schemes: [ColorScheme] = [.light, .dark]) throws {
        let canvas = EditorCanvasModel(original: fixture.image, scale: EditorFixture.scale)
        canvas.renderNow(editor.marks)
        let pixels = CGSize(width: fixture.image.width, height: fixture.image.height)
        let pointsPerPixel = 1 / CGFloat(EditorFixture.scale)
        let size = EditorLayout.contentSize(pixelSize: pixels, pointsPerPixel: pointsPerPixel)
        for scheme in schemes {
            let view = EditorView(editor: editor, canvas: canvas, actions: EditorActions(),
                                  pointsPerPixel: pointsPerPixel, titlebarInset: 0)
                .frame(width: size.width, height: size.height)
                .clipShape(RoundedRectangle(cornerRadius: 10))
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

    private func write(_ image: CGImage, to name: String) throws {
        let path = ProcessInfo.processInfo.environment["EXHIBIT_RENDER_DIR"]
        let folder = path.map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("exhibita-renders")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("\(name).png")
        let data = try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
        try data.write(to: url)
        print("Rendered \(url.path)")
    }
}

/// Renders never write documents.
private struct DiscardingSink: DocumentSaving {
    func save(_ document: CaptureDocument) throws {}
}
