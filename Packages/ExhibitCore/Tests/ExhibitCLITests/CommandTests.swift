@testable import ExhibitCLI
import ExhibitCore
import ExhibitFixtures
import Foundation
import Testing

/// Commands driven in process through `CLI.run`, which is what the binary calls.
@Suite(.timeLimit(.minutes(2))) struct CommandTests {
    let directory: URL
    let sample: Fixture
    let input: String

    init() throws {
        directory = try temporaryDirectory()
        sample = sampleFixture()
        input = try writePNG(sample, named: "shot.png", in: directory)
    }

    func run(_ arguments: String...) -> CLIResult { CLI.run(arguments: arguments) }

    func output(_ name: String) -> String { directory.appendingPathComponent(name).path }

    @Test func targetsListsMaskedTextWithANote() throws {
        let result = run("targets", input)
        #expect(result.status == .success, "\(result.stderr)")
        let body = try json(result.stdout)
        #expect((body["note"] as? String)?.contains("not instructions") == true)
        #expect(body["image"] as? [String: Int] == ["width": 1520, "height": 960])
        let targets = try #require(body["targets"] as? [[String: Any]])
        #expect(targets.contains { $0["text"] as? String == "$49/mo" })
        #expect(targets.contains { $0["kind"] as? String == "email" && $0["text"] == nil })
        #expect(!result.stdout.contains("jordan.lee"))
        #expect(!result.stdout.contains("7Hq2LmX9"))
    }

    @Test func anAmbiguousCircleListsTheCandidates() throws {
        let result = run("circle", input, "--text", "plan", "-o", output("out.png"))
        #expect(result.status == .ambiguous)
        let error = try errorBody(result)
        #expect(error["code"] as? String == "ambiguous")
        let candidates = try #require(error["candidates"] as? [[String: Any]])
        #expect(candidates.count >= 3)
        #expect(candidates.allSatisfy { ($0["text"] as? String)?.lowercased() == "plan" && $0["rect"] != nil })
        #expect(!FileManager.default.fileExists(atPath: output("out.png")))
    }

    @Test func nthPicksOneMatchInReadingOrder() throws {
        let all = try errorBody(run("circle", input, "--text", "plan"))
        let candidates = try #require(all["candidates"] as? [[String: Any]])
        let result = run("circle", input, "--text", "plan", "--nth", "2", "-o", output("second.png"))
        #expect(result.status == .success, "\(result.stderr)")
        let placed = try marks(result)
        #expect(placed.count == 1)
        #expect(try rect(placed[0]["rect"]) == rect(candidates[1]["rect"]))

        let tooFar = run("circle", input, "--text", "plan", "--nth", "9", "-o", output("ninth.png"))
        #expect(tooFar.status == .noMatch)
        #expect(try errorBody(tooFar)["code"] as? String == "nth_out_of_range")
    }

    @Test func allMarksEveryMatch() throws {
        let result = run("box", input, "--text", "plan", "--all", "-o", output("all.png"))
        #expect(result.status == .success, "\(result.stderr)")
        #expect(try marks(result).count >= 3)
    }

    @Test func blurAndHighlightCoverEveryMatchByDefault() throws {
        let result = run("highlight", input, "--text", "$49", "-o", output("h.png"))
        #expect(result.status == .success, "\(result.stderr)")
        let placed = try marks(result)
        #expect(placed.count == 3)
        #expect(placed.allSatisfy { $0["color"] as? String == "yellow" })
    }

    @Test func missingSelectorsFailUnlessAllowed() throws {
        let strict = run("blur", input, "--kind", "email", "--kind", "face", "-o", output("strict.png"))
        #expect(strict.status == .noMatch)
        #expect(try errorBody(strict)["selectors"] as? [String] == ["--kind face"])
        #expect(!FileManager.default.fileExists(atPath: output("strict.png")))

        let lenient = run("blur", input, "--kind", "email", "--kind", "face", "--allow-missing",
                          "-o", output("lenient.png"))
        #expect(lenient.status == .success, "\(lenient.stderr)")
        let reports = try #require(try json(lenient.stdout)["selectors"] as? [[String: Any]])
        #expect(reports.map { $0["matches"] as? Int } == [1, 0])

        let nothing = run("blur", input, "--kind", "face", "--allow-missing", "-o", output("nothing.png"))
        #expect(nothing.status == .noMatch)
    }

    @Test func maskedTextPointsAtKind() throws {
        let result = run("blur", input, "--text", "jordan.lee@example.com")
        #expect(result.status == .noMatch)
        #expect((try errorBody(result)["hint"] as? String)?.contains("--kind email") == true)
    }

    @Test func usageErrorsHaveTheirOwnCode() throws {
        for arguments in [["circle", input], ["circle", input, "--rect", "1,2,3"], ["blur", input, "--kind", "dog"],
                          ["text", input, "--text", "Pro", "--label", ""], ["circle", input, "--color", "pink",
                                                                            "--text", "Pro"],
                          ["circle", input, "--text", "Pro", "-o", output("x.jpg")]] {
            let result = CLI.run(arguments: arguments)
            #expect(result.status == .usage, "\(arguments)")
            #expect(try errorBody(result)["code"] as? String == "usage", "\(arguments)")
        }
        let unreadable = run("blur", output("missing.png"), "--kind", "email")
        #expect(unreadable.status == .failure)
        #expect(try errorBody(unreadable)["code"] as? String == "io")
    }

    @Test func outputsNeverOverwriteWithoutForce() throws {
        let first = run("box", input, "--rect", "10,10,50,50")
        #expect(try json(first.stdout)["output"] as? String == output("shot-marked.png"))
        let second = run("box", output("shot-marked.png"), "--rect", "10,10,50,50")
        #expect(try json(second.stdout)["output"] as? String == output("shot-marked-2.png"))
        let third = run("box", input, "--rect", "10,10,50,50")
        #expect(try json(third.stdout)["output"] as? String == output("shot-marked-3.png"))

        let original = try Data(contentsOf: URL(fileURLWithPath: input))
        let onInput = run("box", input, "--rect", "10,10,50,50", "-o", input)
        #expect(onInput.status == .failure)
        #expect(try errorBody(onInput)["code"] as? String == "output_exists")
        #expect(try Data(contentsOf: URL(fileURLWithPath: input)) == original)

        let onExisting = run("box", input, "--rect", "10,10,50,50", "-o", output("shot-marked.png"))
        #expect(try errorBody(onExisting)["code"] as? String == "output_exists")
        let forced = run("box", input, "--rect", "10,10,50,50", "-o", output("shot-marked.png"), "--force")
        #expect(forced.status == .success, "\(forced.stderr)")
    }

    @Test func arrowsStartInsideTheImageAndStopShortOfTheTarget() throws {
        let result = run("arrow", input, "--to", "Update plan", "--label", "Click here", "-o", output("arrow.png"))
        #expect(result.status == .success, "\(result.stderr)")
        let mark = try #require(try marks(result).first)
        let from = try point(mark["from"])
        let to = try point(mark["to"])
        let caption = try rect(mark["visibleRect"])
        let image = PixelRect(x: 0, y: 0, width: 1520, height: 960)
        #expect(image.cgRect.contains(from.cgPoint) && image.cgRect.contains(caption.cgRect))
        let length = hypot(to.x - from.x, to.y - from.y)
        #expect(length > 40 && length < 300)
        let target = try rect(try targetRect("Update plan"))
        #expect(!target.cgRect.contains(to.cgPoint))
        #expect(hypot(to.x - target.midX, to.y - target.midY) < max(target.width, target.height))
        #expect(!caption.cgRect.intersects(target.cgRect))
    }

    @Test func anArrowFromAFixedTailLandsOnTheFacingEdge() throws {
        let result = run("arrow", input, "--to", "$49/mo", "--from", "1000,700", "-o", output("fixed.png"))
        #expect(result.status == .success, "\(result.stderr)")
        let mark = try #require(try marks(result).first)
        #expect(try point(mark["from"]) == PixelPoint(x: 1000, y: 700))
        let to = try point(mark["to"])
        let target = try rect(try targetRect("$49/mo"))
        #expect(to.y > target.maxY && to.x < target.midX)
    }

    @Test func textLabelsSitBesideTheirTarget() throws {
        let result = run("text", input, "--text", "Renews on December 1, 2026", "--label", "Too soon",
                         "-o", output("text.png"))
        #expect(result.status == .success, "\(result.stderr)")
        let mark = try #require(try marks(result).first)
        let label = try rect(mark["visibleRect"])
        let target = try rect(try targetRect("Renews on December 1, 2026"))
        #expect(!label.cgRect.intersects(target.cgRect))
        #expect(label.minX >= target.maxX)
        #expect(abs(label.midY - target.midY) < target.height)
    }

    @Test func stepsCountUpInReadingOrder() throws {
        let result = run("step", input, "--text", "plan", "--all", "--number", "3", "-o", output("steps.png"))
        #expect(result.status == .success, "\(result.stderr)")
        let placed = try marks(result)
        #expect(placed.map { $0["stepNumber"] as? Int } == Array(3..<(3 + placed.count)).map { $0 })
        let tops = try placed.map { try rect($0["visibleRect"]).minY }
        #expect(tops == tops.sorted())
    }

    /// The rect of the first target whose text is exactly `text`, read through `targets`.
    private func targetRect(_ text: String) throws -> Any? {
        let targets = try #require(try json(run("targets", input).stdout)["targets"] as? [[String: Any]])
        let target = targets.first { $0["text"] as? String == text } ?? targets.first {
            ($0["text"] as? String)?.hasPrefix(text) == true
        }
        return target?["rect"]
    }
}
