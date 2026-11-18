import ExhibitCLI
import ExhibitCore
import ExhibitFixtures
import ExhibitTargets
import Foundation
import Testing

/// The real binary on real files, as an agent runs it.
@Suite(.timeLimit(.minutes(2))) struct EndToEndTests {
    /// The spec's acceptance test: `exhibit blur fixture.png --kind email` hides all fixture emails.
    @Test func blurKindEmailHidesEveryEmail() throws {
        let directory = try temporaryDirectory()
        let fixture = targetsFixture(scale: 2)
        let input = try writePNG(fixture, named: "fixture.png", in: directory)
        #expect(try TargetFinder().findTargets(in: fixture.image).contains { $0.kind == .email })

        let result = try runBinary(["blur", input, "--kind", "email"])
        #expect(result.status == .success, "\(result.stderr)")
        let output = try #require(try json(result.stdout)["output"] as? String)
        #expect(output.hasSuffix("/fixture-marked.png"))

        let found = try TargetFinder().findTargets(in: try readImage(output))
        #expect(!found.contains { $0.kind == .email })
        let lines = found.compactMap(\.text).joined(separator: "\n").lowercased()
        for piece in ["sam", "rivera", "example", "@"] {
            #expect(!lines.contains(piece), "\(piece) still readable in \(lines)")
        }
        // Not even as a masked run: the email's line now reads as the label alone.
        #expect(found.first { $0.text?.hasPrefix("Contact") == true }?.text == "Contact")
        // The rest of the screen is still there.
        #expect(lines.contains("pricing"))
    }

    @Test func anUnmatchedSelectorFailsAndNamesIt() throws {
        let directory = try temporaryDirectory()
        let input = try writePNG(targetsFixture(scale: 2), named: "fixture.png", in: directory)
        let result = try runBinary(["circle", input, "--text", "Nowhere to be found"])
        #expect(result.status == .noMatch)
        #expect(result.stdout.isEmpty)
        let error = try errorBody(result)
        #expect(error["code"] as? String == "no_match")
        #expect(error["selectors"] as? [String] == [#"--text "Nowhere to be found""#])
        #expect((error["message"] as? String)?.contains("Nowhere to be found") == true)
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("fixture-marked.png").path))
    }

    @Test func aJPEGInputGivesAPNG() throws {
        let directory = try temporaryDirectory()
        let input = try writeJPEG(targetsFixture(scale: 2), named: "shot.jpg", in: directory)
        let result = try runBinary(["highlight", input, "--text", "Pricing"])
        #expect(result.status == .success, "\(result.stderr)")
        let output = try #require(try json(result.stdout)["output"] as? String)
        #expect(output.hasSuffix("/shot-marked.png"))
        let data = try Data(contentsOf: URL(fileURLWithPath: output))
        #expect(data.prefix(4) == Data([0x89, 0x50, 0x4E, 0x47]))
    }

    @Test func chainingNeverUndoesABlur() throws {
        let directory = try temporaryDirectory()
        let input = try writePNG(targetsFixture(scale: 2), named: "shot.png", in: directory)
        let first = try runBinary(["blur", input, "--kind", "email"])
        #expect(first.status == .success, "\(first.stderr)")
        let blurred = try #require(try json(first.stdout)["output"] as? String)
        let blurRect = try rect(try marks(first).first?["rect"])

        let second = try runBinary(["circle", blurred, "--text", "Pricing"])
        #expect(second.status == .success, "\(second.stderr)")
        let circled = try #require(try json(second.stdout)["output"] as? String)
        #expect(circled.hasSuffix("/shot-marked-2.png"))

        // Pixels inside the blur are unchanged by the later call, and the email is still unreadable.
        let before = try readImage(blurred)
        let after = try readImage(circled)
        let inner = blurRect.cgRect.insetBy(dx: 4, dy: 4).integral
        #expect(try pixels(of: before, in: inner) == pixels(of: after, in: inner))
        #expect(!(try TargetFinder().findTargets(in: after)).contains { $0.kind == .email })
    }

    @Test func versionAndHelpExitZero() throws {
        let version = try runBinary(["--version"])
        #expect(version.status == .success)
        #expect(version.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == CLI.version)
        let help = try runBinary(["arrow", "--help"])
        #expect(help.status == .success)
        #expect(help.stdout.contains("--from"))
        let bad = try runBinary(["blur"])
        #expect(bad.status == .usage)
        #expect(try errorBody(bad)["code"] as? String == "usage")
    }
}
