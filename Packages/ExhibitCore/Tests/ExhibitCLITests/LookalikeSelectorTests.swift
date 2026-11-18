@testable import ExhibitCLI
import ExhibitCore
import ExhibitFixtures
import ExhibitTargets
import Foundation
import Testing

@Suite(.timeLimit(.minutes(2))) struct LookalikeSelectorTests {
    /// A line stored raw, as an older document or a pure-script word would hold it.
    static let cyrillicLine = Target(
        kind: .text, text: "Астe Dashboard", rect: PixelRect(x: 10, y: 10, width: 280, height: 30),
        spans: [TextSpan(start: 0, length: 4, rect: PixelRect(x: 10, y: 10, width: 80, height: 30)),
                TextSpan(start: 5, length: 9, rect: PixelRect(x: 100, y: 10, width: 190, height: 30))]
    )

    @Test func textAndRegexMatchWhatAPersonReads() throws {
        for selector in [Selector.text("Acme"), .text("acme dash"), .regex("^Acme\\b"), .text("Астe")] {
            let found = try SelectorMatcher.candidates(for: selector, in: [Self.cyrillicLine])
            #expect(found.count == 1, "\(selector.description)")
            #expect(found.first?.rect.minX == 10, "\(selector.description)")
        }
    }

    @Test func theRealBinaryRedactsAKeyReadWithLookalikes() throws {
        let directory = try temporaryDirectory()
        let input = try writePNG(lookalikeFixture(), named: "acme.png", in: directory)

        let blurred = try runBinary(["blur", input, "--kind", "key"])
        #expect(blurred.status == .success, "\(blurred.stderr)")
        let output = try #require(try json(blurred.stdout)["output"] as? String)
        let after = try TargetFinder().findTargets(in: try readImage(output))
        #expect(!after.contains { $0.kind == .key })
        #expect(!after.compactMap(\.text).joined().lowercased().contains("zx81"))

        let circled = try runBinary(["circle", input, "--text", "Acme Dashboard", "-o",
                                     directory.appendingPathComponent("circled.png").path])
        #expect(circled.status == .success, "\(circled.stderr)")
    }
}
