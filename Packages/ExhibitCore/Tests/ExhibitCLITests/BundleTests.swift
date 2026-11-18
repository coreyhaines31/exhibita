@testable import ExhibitCLI
import ExhibitCore
import ExhibitFixtures
import ExhibitTargets
import Foundation
import Testing

@Suite(.timeLimit(.minutes(2))) struct BundleTests {
    let directory: URL

    init() throws {
        directory = try temporaryDirectory()
    }

    func makeBundle(targets: [Target], marks: [Mark] = []) throws -> URL {
        let fixture = sampleFixture()
        let document = CaptureDocument(size: PixelSize(width: fixture.image.width, height: fixture.image.height),
                                       scale: 2, targets: targets, marks: marks)
        return try CaptureBundle.save(document, original: fixture.image, in: directory)
    }

    @Test func marksAreAppendedAndTargetsReused() throws {
        // A target that is not in the image: only the document knows it, so finding it proves OCR did not run.
        let planted = Target(kind: .text, text: "Zebra crossing", rect: PixelRect(x: 100, y: 600, width: 200, height: 30))
        let earlier = Mark.blur(PixelRect(x: 10, y: 10, width: 40, height: 40))
        let bundle = try makeBundle(targets: [planted], marks: [earlier])

        let result = CLI.run(arguments: ["circle", bundle.path, "--text", "zebra"])
        #expect(result.status == .success, "\(result.stderr)")
        let body = try json(result.stdout)
        #expect(body["targetsReused"] as? Bool == true)
        #expect(body["bundle"] as? String == bundle.path)
        let output = try #require(body["output"] as? String)
        let name = bundle.deletingPathExtension().lastPathComponent
        #expect(output == directory.appendingPathComponent("\(name)-marked.png").path)

        let saved = try CaptureBundle.load(from: bundle).document
        #expect(saved.marks.count == 2)
        #expect(saved.marks[0] == earlier)
        #expect(saved.marks[1].kind == .circle && saved.marks[1].targetID == planted.id)
        #expect(saved.targets == [planted])

        let again = CLI.run(arguments: ["box", bundle.path, "--text", "zebra"])
        #expect(again.status == .success, "\(again.stderr)")
        #expect(try CaptureBundle.load(from: bundle).document.marks.map(\.kind) == [.blur, .circle, .box])
    }

    @Test func aBundleWithoutTargetsGetsThemOnce() throws {
        let bundle = try makeBundle(targets: [])
        let result = CLI.run(arguments: ["blur", bundle.path, "--kind", "email"])
        #expect(result.status == .success, "\(result.stderr)")
        #expect(try json(result.stdout)["targetsReused"] as? Bool == false)
        let saved = try CaptureBundle.load(from: bundle).document
        #expect(saved.targets.contains { $0.kind == .email })
        #expect(saved.marks.map(\.kind) == [.blur])
        // The original stays clean: marks live in document.json only.
        #expect(try Data(contentsOf: bundle.appendingPathComponent("original.png")) == PNG.encode(sampleFixture().image))
    }

    @Test func exportsNeverLandInsideABundle() throws {
        let bundle = try makeBundle(targets: [])
        let result = CLI.run(arguments: ["box", bundle.path, "--rect", "1,1,5,5", "--force",
                                         "-o", bundle.appendingPathComponent("original.png").path])
        #expect(result.status == .usage)
    }
}
