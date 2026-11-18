import CoreGraphics
import ExhibitCore
import ExhibitFixtures
@testable import ExhibitTargets
import Foundation
import Testing

/// Expects `found` to match a CoreText box: the same left and right edges within a few pixels, and vertically
/// inside the line's typographic box (ink is shorter than ascent plus descent) but at least half its height.
func expectClose(_ found: PixelRect?, _ expected: PixelRect, scale: Double, _ what: String,
                 sourceLocation: SourceLocation = #_sourceLocation) {
    guard let found = found?.standardized else {
        Issue.record("\(what): no box", sourceLocation: sourceLocation)
        return
    }
    let slack = 3 * scale
    let fits = abs(found.minX - expected.minX) <= slack && abs(found.maxX - expected.maxX) <= slack
        && found.minY >= expected.minY - slack && found.maxY <= expected.maxY + slack
        && found.height >= expected.height * 0.5
    #expect(fits, "\(what): found \(found), expected about \(expected)", sourceLocation: sourceLocation)
}

private func lines(_ targets: [Target]) -> [Target] { targets.filter { $0.kind == .text } }

private func line(_ targets: [Target], startingWith prefix: String) -> Target? {
    lines(targets).first { $0.text?.hasPrefix(prefix) == true }
}

@Suite struct TargetFinderTests {
    @Test(arguments: [1.0, 2.0])
    func linesAreFoundWithTightBoxes(scale: Double) throws {
        let fixture = targetsFixture(scale: scale)
        let targets = try TargetFinder().findTargets(in: fixture.image)
        let expected: [(String, String)] = [
            ("See Pricing and plans", "pricing-line"), ("Contact", "email-line"), ("Card", "card-line"),
            ("Call", "phone-line"), ("Token", "key-line"), ("Muted footnote text", "muted-line")
        ]
        for (prefix, name) in expected {
            let found = line(targets, startingWith: prefix)
            #expect(found != nil, "no line starting \(prefix) in \(lines(targets).compactMap(\.text))")
            expectClose(found?.rect, fixture[name], scale: scale, name)
            #expect((found?.confidence ?? 0) > 0.3)
        }
        #expect(line(targets, startingWith: "See Pricing and plans")?.text == "See Pricing and plans")
    }

    @Test(arguments: [1.0, 2.0])
    func aWordInsideALineResolvesWithoutOCR(scale: Double) throws {
        let fixture = targetsFixture(scale: scale)
        let found = try #require(line(try TargetFinder().findTargets(in: fixture.image), startingWith: "See Pricing"))
        // Through JSON, as unit 3 will read it back from document.json.
        let reloaded = try JSONDecoder().decode(Target.self, from: try JSONEncoder().encode(found))
        let text = try #require(reloaded.text)
        let range = try #require(text.range(of: "Pricing"))
        expectClose(reloaded.rect(for: range), fixture["Pricing"], scale: scale, "Pricing")
        #expect(reloaded.spans?.count == 4)
    }

    @Test(arguments: [1.0, 2.0])
    func eachSensitiveKindIsFoundThroughOCR(scale: Double) throws {
        let fixture = targetsFixture(scale: scale)
        let targets = try TargetFinder().findTargets(in: fixture.image)
        for (kind, name) in [(TargetKind.email, "email"), (.card, "card"), (.phone, "phone"), (.key, "key")] {
            let matches = targets.filter { $0.kind == kind }
            #expect(matches.count == 1, "\(kind.rawValue): \(matches)")
            expectClose(matches.first?.rect, fixture[name], scale: scale, name)
            #expect(matches.first?.text == nil)
        }
        #expect(!targets.contains { $0.kind == .face })
    }

    @Test func sensitiveTextNeverReachesTheDocument() throws {
        let targets = try TargetFinder().findTargets(in: targetsFixture(scale: 2).image)
        let json = try #require(String(bytes: try JSONEncoder().encode(targets), encoding: .utf8))
        for value in [FixtureValues.email, FixtureValues.githubKey, "4242", "555-0132"] {
            #expect(!json.contains(value), "\(value) leaked")
        }
        let email = try #require(line(targets, startingWith: "Contact"))
        #expect(email.text == "Contact " + String(repeating: "\u{2022}", count: FixtureValues.email.utf16.count))
    }

    @Test func theSampleFindsItsEmailAndKey() throws {
        let fixture = sampleFixture()
        let targets = try TargetFinder().findTargets(in: fixture.image)
        let email = try #require(targets.first { $0.kind == .email })
        expectClose(email.rect, fixture["email"], scale: 2, "email")
        let key = try #require(targets.first { $0.kind == .key })
        expectClose(key.rect, fixture["key"], scale: 2, "key")
        #expect(line(targets, startingWith: "Manage your plan") != nil)
    }

    @Test func outputIsOrderedAndRepeatable() throws {
        let image = targetsFixture(scale: 2).image
        let first = try TargetFinder().findTargets(in: image)
        let second = try TargetFinder().findTargets(in: image)
        let strip = { (targets: [Target]) in targets.map { [$0.kind.rawValue, $0.text ?? "", "\($0.rect)"] } }
        #expect(strip(first) == strip(second))
        #expect(TargetFinder.ordered(first).map(\.id) == first.map(\.id))
        let tops = first.map(\.rect.minY)
        #expect(tops == tops.sorted())
    }

    @Test func emptyImagesHaveNoTargets() throws {
        let blank = makeImage(width: 64, height: 64) { context in
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        }
        #expect(try TargetFinder().findTargets(in: blank).isEmpty)
    }
}

@Suite struct TargetFinderUnitTests {
    @Test func masksKeepUTF16Offsets() {
        let text = "a😀 key"
        let masked = TargetFinder.masked(text, ranges: [NSRange(location: 4, length: 3)])
        #expect(masked == "a😀 \u{2022}\u{2022}\u{2022}")
        #expect(masked.utf16.count == text.utf16.count)
    }

    @Test func lineTargetsSplitOutSensitiveMatches() {
        let text = "Mail sam@example.com"
        let spans = [TextSpan(start: 0, length: 4, rect: PixelRect(x: 0, y: 0, width: 40, height: 10)),
                     TextSpan(start: 5, length: 15, rect: PixelRect(x: 50, y: 0, width: 150, height: 10))]
        let targets = TargetFinder.lineTargets(text: text, rect: PixelRect(x: 0, y: 0, width: 200, height: 10),
                                               confidence: 1, spans: spans)
        #expect(targets.map(\.kind) == [.text, .email])
        #expect(targets[1].rect == PixelRect(x: 50, y: 0, width: 150, height: 10))
        #expect(targets[1].text == nil)
    }

    @Test func wordRangesSkipWhitespace() {
        let text = "  See  Pricing\tnow "
        #expect(TargetFinder.wordRanges(in: text).map { String(text[$0]) } == ["See", "Pricing", "now"])
    }

    @Test func orderingIsTopToBottomThenLeftToRight() {
        let make = { (x: Double, y: Double, kind: TargetKind) in
            Target(kind: kind, rect: PixelRect(x: x, y: y, width: 5, height: 5))
        }
        let targets = [make(50, 10, .text), make(0, 20, .text), make(0, 10, .key), make(0, 10, .text)]
        let ordered = TargetFinder.ordered(targets)
        #expect(ordered.map(\.rect.minY) == [10, 10, 10, 20])
        #expect(ordered.map(\.kind) == [.text, .key, .text, .text])
        #expect(ordered[2].rect.minX == 50)
    }
}

@Suite struct VisionGeometryTests {
    @Test func normalizedBottomLeftBecomesTopLeftPixels() {
        // A box in the top-left quarter of a 200 by 100 image, in Vision's bottom-left space.
        let rect = VisionGeometry.pixelRect(CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5), width: 200, height: 100)
        #expect(rect == PixelRect(x: 0, y: 0, width: 100, height: 50))
        let bottomRight = VisionGeometry.pixelRect(CGRect(x: 0.75, y: 0, width: 0.25, height: 0.1), width: 400,
                                                   height: 300)
        #expect(bottomRight == PixelRect(x: 300, y: 270, width: 100, height: 30))
    }

    @Test func inkTrimShrinksToGlyphsOnPlainBackgrounds() throws {
        let image = makeImage(width: 40, height: 20) { context in
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 40, height: 20))
            context.setFillColor(CGColor(gray: 0, alpha: 1))
            context.fill(CGRect(x: 10, y: 5, width: 12, height: 8))
        }
        let grid = try #require(InkGrid(image))
        let trimmed = grid.trimmed(PixelRect(x: 2, y: 1, width: 30, height: 17))
        #expect(trimmed == PixelRect(x: 10, y: 5, width: 12, height: 8))
        // A box that cuts into the ink keeps all the ink it holds.
        let cut = grid.trimmed(PixelRect(x: 12, y: 1, width: 20, height: 17))
        #expect(cut == PixelRect(x: 12, y: 5, width: 10, height: 8))
    }

    @Test func inkTrimHandlesABoxThatSpillsOffAButton() throws {
        // White text on a blue button, with the OCR box running past the button onto a gray window.
        let image = makeImage(width: 60, height: 20) { context in
            context.setFillColor(CGColor(gray: 0.93, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 60, height: 20))
            context.setFillColor(CGColor(srgbRed: 0, green: 0.48, blue: 1, alpha: 1))
            context.fill(CGRect(x: 8, y: 0, width: 52, height: 20))
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: 20, y: 6, width: 20, height: 8))
        }
        let grid = try #require(InkGrid(image))
        #expect(grid.trimmed(PixelRect(x: 2, y: 2, width: 52, height: 16)) == PixelRect(x: 20, y: 6, width: 20, height: 8))
    }

    @Test func inkTrimLeavesTinyOrBlankBoxesAlone() throws {
        let grid = try #require(InkGrid(makeImage(width: 10, height: 10) { context in
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
        }))
        let blank = PixelRect(x: 1, y: 1, width: 8, height: 8)
        #expect(grid.trimmed(blank) == blank)
        let tiny = PixelRect(x: 1, y: 1, width: 2, height: 2)
        #expect(grid.trimmed(tiny) == tiny)
    }
}
