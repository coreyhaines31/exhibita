import AppKit
import CoreGraphics
import ExhibitCore
import ExhibitEditor
import ExhibitInterpret
import PanelKit
import SwiftUI
import XCTest

/// Renders the editor in each dictation state with `ImageRenderer`. Speech is a fake that hears what the test
/// says; the model is a fake. No microphone, no permission prompt, no window, no network.
///
/// `EXHIBIT_RENDER_DIR=<folder>` writes the PNGs there; the repo keeps them in `docs/samples/app`.
@MainActor
final class DictationRenderTests: XCTestCase {
    private let fixture = EditorFixture()

    override func setUp() async throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        PanelFont.register()
    }

    private func makeSession(_ speech: StubTranscriber = StubTranscriber(),
                             model: (any Interpreter)? = nil) -> DictationSession {
        let owner = DocumentOwner(document: fixture.document(withTargets: true), targetsLoaded: true,
                                  writer: DocumentWriter(sink: NoSink(), delay: 60))
        return DictationSession(editor: CaptureEditor(owner: owner), original: fixture.image, transcriber: speech,
                                model: { model })
    }

    private func wait(_ condition: () -> Bool) async {
        for _ in 0..<500 where !condition() {
            try? await Task.sleep(for: .milliseconds(2))
        }
        XCTAssertTrue(condition())
    }

    func testRendersDictation() async throws {
        // Holding D: the live transcript.
        let speech = StubTranscriber()
        let listening = makeSession(speech)
        listening.press(pointer: fixture.center("update"))
        await wait { listening.isListening }
        speech.hear("blur the emails and circle update")
        try render(listening, name: "editor-listening")

        // Released, the grammar declined and the local model is reading it.
        let gate = StubGate()
        let answer = Interpretation(operations: [InterpretedOperation(mark: .circle, picks: [.id(fixture.updateID)])])
        let working = makeSession(model: StubModel(answer: answer, gate: gate))
        working.submit("point out where to upgrade")
        await wait { working.editor.dictation == .interpreting(transcript: "point out where to upgrade",
                                                                usingModel: true) }
        try render(working, name: "editor-interpreting", schemes: [.light])
        gate.open()

        // Marks first, then the sentence naming each one.
        let applied = makeSession()
        applied.submit("blur the emails and circle update plan")
        await wait { applied.editor.dictation?.changedMarks == true }
        try render(applied, name: "editor-applied")

        let partial = makeSession()
        partial.submit("blur the emails and the card numbers")
        await wait { !partial.isBusy }
        try render(partial, name: "editor-partial", schemes: [.light])

        let needsModel = makeSession()
        needsModel.submit("hide anything that identifies the customer")
        await wait { !needsModel.isBusy }
        try render(needsModel, name: "editor-needs-model")

        let denied = StubTranscriber()
        denied.readiness = .microphoneDenied
        let microphone = makeSession(denied)
        microphone.press()
        await wait { !microphone.isBusy }
        try render(microphone, name: "editor-microphone-denied", schemes: [.light])

        let typing = makeSession()
        typing.beginTyping()
        try render(typing, name: "editor-typing", schemes: [.light])
    }

    func testDictatedMarksAreTheRenderersAndUndoTogether() async throws {
        let session = makeSession()
        session.submit("blur the emails and blur the keys")
        await wait { !session.isBusy }
        XCTAssertEqual(session.editor.marks.map(\.kind), [.blur, .blur])
        let canvas = EditorCanvasModel(original: fixture.image, scale: EditorFixture.scale)
        canvas.renderNow(session.editor.marks)
        XCTAssertEqual(try PNG.encode(XCTUnwrap(canvas.rendered)),
                       try EditorExport.png(session.editor.document, original: fixture.image))
        session.editor.undo()
        XCTAssertTrue(session.editor.marks.isEmpty)
    }

    // MARK: - Rendering

    private func render(_ session: DictationSession, name: String, schemes: [ColorScheme] = [.light, .dark]) throws {
        let canvas = EditorCanvasModel(original: fixture.image, scale: EditorFixture.scale)
        canvas.renderNow(session.editor.marks)
        let pixels = CGSize(width: fixture.image.width, height: fixture.image.height)
        let pointsPerPixel = 1 / CGFloat(EditorFixture.scale)
        let size = EditorLayout.contentSize(pixelSize: pixels, pointsPerPixel: pointsPerPixel)
        for scheme in schemes {
            let view = EditorView(editor: session.editor, canvas: canvas, actions: EditorActions(),
                                  pointsPerPixel: pointsPerPixel, titlebarInset: 0, dictation: session)
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

private struct NoSink: DocumentSaving {
    func save(_ document: CaptureDocument) throws {}
}

/// Hears what the test says. Never touches the microphone or asks for permission.
@MainActor
final class StubTranscriber: SpeechTranscribing {
    var readiness: SpeechReadiness = .ready
    var final = ""
    private var partial: (@MainActor (String) -> Void)?

    func prepare() async -> SpeechReadiness { readiness }
    func download(progress: @escaping @MainActor (Double) -> Void) async throws {}
    func start(hints: [String], partial: @escaping @MainActor (String) -> Void) async throws { self.partial = partial }
    func hear(_ text: String) { partial?(text) }
    func finish() async -> String { final }
    func cancel() { partial = nil }
}

final class StubGate: @unchecked Sendable {
    private let lock = NSLock()
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private var isOpen = false

    func wait() async {
        await withCheckedContinuation { continuation in
            let resumeNow = lock.withLock {
                if isOpen { return true }
                waiting.append(continuation)
                return false
            }
            if resumeNow { continuation.resume() }
        }
    }

    func open() {
        let resumed = lock.withLock {
            isOpen = true
            defer { waiting.removeAll() }
            return waiting
        }
        resumed.forEach { $0.resume() }
    }
}

private struct StubModel: Interpreter {
    let answer: Interpretation
    let gate: StubGate
    var name: String { "stub-model" }

    func interpret(_ request: InterpretRequest) async throws -> InterpretOutcome {
        await gate.wait()
        return .understood(answer)
    }
}
