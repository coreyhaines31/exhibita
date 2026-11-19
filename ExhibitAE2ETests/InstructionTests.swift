import AppKit
@testable import ExhibitA
import ExhibitCore
import ExhibitEditor
import XCTest

/// 4. Typed instructions through / in the real window, against what `exhibit say` writes for the same capture;
/// "Needs a model" with no model set up; and D with speech denied, through an injected transcriber so the
/// microphone and the permission prompts are never touched.
@MainActor
final class InstructionTests: XCTestCase {
    private let fixture = teamFixture()

    override func setUp() async throws {
        try E2E.begin()
    }

    override func tearDown() async throws {
        E2E.closeEverything()
        EditorWindowController.makeTranscriber = { SpeechTranscription.make() }
    }

    private func open() async throws -> EditorDriver {
        try EditorDriver(await E2E.captureAndEdit(fixture.image, scale: fixture.scale, appName: "Acme Cloud",
                                                  windowTitle: "Team"))
    }

    private func typeInstruction(_ text: String, in editor: EditorDriver) async {
        await editor.key("/")
        await E2E.wait("the instruction field") { editor.controller.dictation.isTyping }
        await E2E.settle(150)
        await editor.type(text)
        await editor.special(Events.returnKey)
        await E2E.wait("the instruction to finish") {
            !editor.controller.dictation.isTyping && !editor.controller.dictation.isBusy
                && editor.editor.dictation != nil
        }
    }

    func testTypedInstructionMatchesSay() async throws {
        let instruction = "blur the emails and circle pricing"
        let editor = try await open()

        // `exhibit say` on a copy of the same capture: same original, same targets, no marks.
        let copies = E2E.seam.supportDirectory.appendingPathComponent("say-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: copies, withIntermediateDirectories: true)
        let copy = try CaptureBundle.save(editor.editor.document, original: fixture.image, in: copies)
        let said = try await E2E.exhibit(["say", copy.path, instruction, "-o", copies.appendingPathComponent("o.png").path])
        XCTAssertEqual(said.status, 0, said.stderr)
        let saidMarks = try CaptureBundle.load(from: copy).document.marks
        let summary = try XCTUnwrap(said.json["summary"] as? String, said.stdout)

        let start = ContinuousClock.now
        await typeInstruction(instruction, in: editor)
        print("E2E: typed instruction to marks \((ContinuousClock.now - start).formatted(.units(allowed: [.milliseconds])))")
        let marks = editor.editor.marks
        XCTAssertEqual(marks.filter { $0.kind == .blur }.count, 2, "both emails")
        XCTAssertEqual(marks.filter { $0.kind == .circle }.count, 1, "pricing")
        XCTAssertEqual(marks.map(\.shape), saidMarks.map(\.shape), "the same marks as exhibit say")
        let status = try XCTUnwrap(editor.editor.status.text)
        XCTAssertTrue(status.contains(summary), "status \(status) names \(summary)")
        try await editor.picture(named: "editor-after-instruction")

        await editor.key("z", .command)
        XCTAssertTrue(editor.editor.marks.isEmpty, "one ⌘Z takes back the whole instruction")
    }

    func testDeclinedSentenceNeedsAModel() async throws {
        XCTAssertFalse(FreeFormSettings.shared.settings.enabled, "no model in the throwaway settings")
        let editor = try await open()
        await typeInstruction("make the important part stand out", in: editor)
        guard case .needsModel = editor.editor.dictation else {
            return XCTFail("expected Needs a model, got \(String(describing: editor.editor.dictation))")
        }
        XCTAssertTrue(editor.editor.status.text?.contains("Needs a local model, and none is set up. Choose one in Settings") == true,
                      "\(String(describing: editor.editor.status.text))")
        XCTAssertTrue(editor.editor.marks.isEmpty)
        try await editor.picture(named: "editor-needs-model")
    }

    func testHoldingDWithSpeechDeniedSaysSoWithoutAsking() async throws {
        let fake = DeniedTranscriber()
        EditorWindowController.makeTranscriber = { fake }
        let editor = try await open()
        Events.key("d", in: editor.window)
        await E2E.wait("the denied state") { editor.editor.dictation == .microphoneDenied }
        XCTAssertEqual(fake.prepared, 1, "asked the transcriber once")
        XCTAssertEqual(fake.started, 0, "never listened")
        XCTAssertNotNil(editor.editor.status.text)
        try await editor.picture(named: "editor-microphone-denied")
    }
}

/// Speech that says the microphone is off, as macOS does after "Don't Allow". Never touches audio.
@MainActor
private final class DeniedTranscriber: SpeechTranscribing {
    var prepared = 0
    var started = 0

    func prepare() async -> SpeechReadiness {
        prepared += 1
        return .microphoneDenied
    }

    func download(progress: @escaping @MainActor (Double) -> Void) async throws {}

    func start(hints: [String], partial: @escaping @MainActor (String) -> Void) async throws {
        started += 1
    }

    func finish() async -> String { "" }

    func cancel() {}
}
