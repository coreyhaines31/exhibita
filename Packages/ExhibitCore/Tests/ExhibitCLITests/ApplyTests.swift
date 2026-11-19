@testable import ExhibitCLI
import ExhibitCore
import ExhibitFixtures
import ExhibitTargets
import Foundation
import Testing

@Suite(.timeLimit(.minutes(2))) struct ApplyTests {
    let directory: URL
    let input: String

    init() throws {
        directory = try temporaryDirectory()
        input = try writePNG(sampleFixture(), named: "shot.png", in: directory)
    }

    func marksFile(_ text: String) throws -> String {
        let url = directory.appendingPathComponent("marks-\(UUID().uuidString).json")
        try Data(text.utf8).write(to: url)
        return url.path
    }

    @Test func aBatchRendersOnce() throws {
        let file = try marksFile("""
            [
              {"kind": "blur", "kinds": ["email", "key"]},
              {"kind": "circle", "text": "$49/mo"},
              {"kind": "arrow", "to": "Update plan", "label": "Click here", "color": "blue"},
              {"kind": "box", "rect": {"x": 20, "y": 20, "width": 40, "height": 30}},
              {"kind": "arrow", "from": {"x": 100, "y": 900}, "to": {"x": 200, "y": 800}},
              {"kind": "step", "text": "Billing", "nth": 1},
              {"kind": "step", "text": "Cancel plan"}
            ]
            """)
        let output = directory.appendingPathComponent("batch.png").path
        let result = CLI.run(arguments: ["apply", input, file, "-o", output])
        #expect(result.status == .success, "\(result.stderr)")
        let placed = try marks(result)
        #expect(placed.map { $0["kind"] as? String } == ["blur", "blur", "circle", "arrow", "box", "arrow", "step", "step"])
        #expect(placed.map { $0["entry"] as? Int } == [0, 0, 1, 2, 3, 4, 5, 6])
        #expect(placed[3]["color"] as? String == "blue")
        #expect(try point(placed[5]["to"]) == PixelPoint(x: 200, y: 800))
        // Steps without a number continue across entries.
        #expect(placed.suffix(2).map { $0["stepNumber"] as? Int } == [1, 2])
        let found = try TargetFinder().findTargets(in: try readImage(output))
        #expect(!found.contains { $0.kind == .email || $0.kind == .key })
    }

    @Test func theWrappedFormIsAccepted() throws {
        let file = try marksFile(#"{"marks": [{"kind": "highlight", "text": ["Pro", "Team"], "nth": 1}]}"#)
        let result = CLI.run(arguments: ["apply", input, file, "-o", directory.appendingPathComponent("w.png").path])
        #expect(result.status == .success, "\(result.stderr)")
        #expect(try marks(result).count == 2)
    }

    @Test func aFailingEntryWritesNothingAndSaysWhich() throws {
        let output = directory.appendingPathComponent("never.png").path
        let file = try marksFile(#"[{"kind": "blur", "kinds": "email"}, {"kind": "circle", "to": "Nowhere at all"}]"#)
        let result = CLI.run(arguments: ["apply", input, file, "-o", output])
        #expect(result.status == .noMatch)
        #expect((try errorBody(result)["message"] as? String)?.hasPrefix("marks[1]: ") == true)
        #expect(!FileManager.default.fileExists(atPath: output))
    }

    @Test(arguments: [
        (#"[{"kind": "circle", "txt": "Pro"}]"#, "unknown field \"txt\""),
        (#"[{"kind": "squiggle", "text": "Pro"}]"#, "unknown kind"),
        (#"[{"kind": "blur", "kinds": ["dog"]}]"#, "Unknown kind"),
        (#"[{"kind": "box", "rect": {"x": 1}}]"#, "marks[0].rect"),
        (#"[]"#, "no marks"),
        ("not json", "not valid JSON")
    ])
    func badFilesAreUsageErrors(text: String, fragment: String) throws {
        let result = CLI.run(arguments: ["apply", input, try marksFile(text)])
        #expect(result.status == .usage)
        let error = try errorBody(result)
        #expect(error["code"] as? String == "invalid_marks")
        #expect((error["message"] as? String)?.contains(fragment) == true, "\(error)")
    }
}
