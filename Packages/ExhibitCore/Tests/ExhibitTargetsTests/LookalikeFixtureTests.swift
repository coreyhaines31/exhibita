import ExhibitCore
import ExhibitFixtures
@testable import ExhibitTargets
import Foundation
import Testing

@Suite(.timeLimit(.minutes(2))) struct LookalikeFixtureTests {
    /// Guards the fixture itself: if Vision stops misreading it, the end-to-end test no longer covers issue 20 and
    /// the fixture needs a new misread.
    @Test func visionStillMisreadsTheFixture() throws {
        // Through the Vision queue: a direct `perform` here deadlocked against other tests' Vision work.
        let lines = try TargetFinder.rawLines(in: lookalikeFixture().image)
        #expect(lines.contains { $0.unicodeScalars.contains { $0.value > 0x7F } },
                "Vision read the look-alike fixture as plain ASCII (\(lines)); pick a new misread for issue 20.")
    }

    @Test func targetsReadAsLatinAndTheKeyIsFound() throws {
        let fixture = lookalikeFixture()
        let targets = try TargetFinder().findTargets(in: fixture.image)
        #expect(targets.contains { $0.kind == .text && $0.text == "Acme Dashboard" }, "\(targets.compactMap(\.text))")
        let key = try #require(targets.first { $0.kind == .key })
        // The key shares a word with "ACME_KEY=", so its box is a proportional slice of that word: check it covers
        // the token, within the 2 pixels a blur grows by.
        let expected = fixture["key"]
        #expect(key.rect.minX <= expected.minX + 2 && key.rect.maxX >= expected.maxX - 2, "\(key.rect) vs \(expected)")
        #expect(!targets.compactMap(\.text).joined().contains("Zx81"))
    }
}
