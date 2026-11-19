@testable import ExhibitCLI
import ExhibitCore
@testable import ExhibitEditor
import ExhibitInterpret
import Foundation
import Testing

/// An instruction applied in the editor gives exactly the marks `exhibit say` writes for the same capture and
/// targets, and the same summary sentence.
@MainActor
@Suite(.timeLimit(.minutes(2))) struct InstructionEquivalenceTests {
    nonisolated static let instructions = [
        "blur the emails",
        "circle renews and point at update plan",
        "highlight this",
        "blur the keys and box update plan",
        "number update plan and renews"
    ]

    @Test(arguments: instructions) func editorMarksMatchSay(_ instruction: String) throws {
        let fixture = EditorFixture()
        let pointer = fixture.point(in: fixture["update"])
        var document = fixture.document
        // A mark already there, so both sides plan around the same existing marks.
        document.marks = [.box(PixelRect(x: 40, y: 40, width: 200, height: 60), color: .blue)]

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("equivalence-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let bundle = try CaptureBundle.save(document, original: fixture.fixture.image, in: directory)
        let result = CLI.run(arguments: ["say", bundle.path, instruction, "--pointer", "\(pointer.x),\(pointer.y)",
                                         "-o", directory.appendingPathComponent("out.png").path],
                             environment: [:])
        #expect(result.status == .success, "\(result.stderr)")
        let said = try CaptureBundle.load(from: bundle).document.marks
        let summary = try #require(try JSONSerialization.jsonObject(with: Data(result.stdout.utf8)) as? [String: Any])
        let sentence = try #require(summary["summary"] as? String)

        let editor = makeEditor(fixture)
        editor.owner.setMarks(document.marks)
        let interpretation = try #require(GrammarInterpreter.interpret(
            InterpretRequest(instruction: instruction, targets: editor.document.targets, pointer: pointer)
        ).interpretation)
        let applied = editor.apply(interpretation, original: fixture.fixture.image)

        #expect(said.count > document.marks.count, "say marked something")
        #expect(Self.shapes(editor.marks) == Self.shapes(said))
        switch applied {
        case .applied(let text, _), .partial(let text, _): #expect(text == sentence)
        default: Issue.record("expected marks, got \(applied)")
        }
    }

    @Test func aBatchIsOneUndoStep() throws {
        let fixture = EditorFixture()
        let editor = makeEditor(fixture)
        let interpretation = try #require(GrammarInterpreter.interpret(
            InterpretRequest(instruction: "blur the emails and circle update plan", targets: editor.document.targets)
        ).interpretation)
        let result = editor.apply(interpretation, original: fixture.fixture.image)
        #expect(result.changedMarks)
        #expect(editor.marks.count == 2)
        editor.undo()
        #expect(editor.marks.isEmpty)
        #expect(!editor.canUndo)
    }

    @Test func aBlurOnPartOfALineCoversTheWholeLine() throws {
        let fixture = EditorFixture()
        let editor = makeEditor(fixture)
        let renews = fixture.renewsID
        let narrow = Interpretation(operations: [
            InterpretedOperation(mark: .blur, picks: [.part(renews, start: 0, length: 6)]),
            InterpretedOperation(mark: .circle, picks: [.part(renews, start: 0, length: 6)])
        ])
        _ = editor.apply(narrow, original: fixture.fixture.image)
        let line = fixture["renews"]
        let blur = try #require(editor.marks.first { $0.kind == .blur })
        #expect(blur.bounds.covers(line), "the blur covers the whole line")
        let circle = try #require(editor.marks.first { $0.kind == .circle })
        #expect(circle.bounds.width < line.width, "other marks still go on the phrase")
    }

    @Test func nothingFoundChangesNothing() throws {
        let fixture = EditorFixture()
        let editor = makeEditor(fixture)
        let result = editor.apply(Interpretation(operations: [], notFound: ["avatar"]), original: fixture.fixture.image)
        #expect(result == .nothingFound(summary: "Couldn't find: avatar."))
        #expect(editor.marks.isEmpty)
        #expect(!editor.canUndo)
    }

    /// Marks without their ids, which are new on each side.
    static func shapes(_ marks: [Mark]) -> [Mark] {
        marks.map { mark in
            var copy = mark
            copy.id = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
            return copy
        }
    }
}
