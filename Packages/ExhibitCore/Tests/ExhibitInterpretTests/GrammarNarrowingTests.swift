import ExhibitCore
@testable import ExhibitInterpret
import Foundation
import Testing

/// A footer line with one span per word, the way OCR reads it, and a line that says "Docs" twice.
private enum Footer {
    static let text = "Pricing · Docs · Sign out"
    static let line = Target(kind: .text, text: text, rect: PixelRect(x: 100, y: 500, width: 250, height: 14),
                             spans: spans(for: text, x: 100, y: 500))
    static let twice = Target(kind: .text, text: "Docs and more Docs", rect: PixelRect(x: 100, y: 540, width: 180,
                                                                                      height: 14))
    static let targets = [line, twice]

    /// One span per run of non-space characters, 10 pixels per character.
    static func spans(for text: String, x: Double, y: Double) -> [TextSpan] {
        var spans: [TextSpan] = []
        var start: Int?
        let units = Array(text.utf16)
        for index in 0...units.count {
            let isSpace = index == units.count || units[index] == 0x20
            if !isSpace, start == nil { start = index }
            if isSpace, let first = start {
                spans.append(TextSpan(start: first, length: index - first,
                                      rect: PixelRect(x: x + Double(first) * 10, y: y, width: Double(index - first) * 10,
                                                      height: 14)))
                start = nil
            }
        }
        return spans
    }

    static func picks(_ instruction: String) -> [TargetPick]? {
        GrammarInterpreter.interpret(InterpretRequest(instruction: instruction, targets: targets))
            .interpretation?.operations.flatMap(\.picks)
    }

    static func part(_ phrase: String) -> TargetPick {
        let range = (text as NSString).range(of: phrase)
        return .part(line.id, start: range.location, length: range.length)
    }
}

/// When the phrase is only part of a line, marks other than blur go on the phrase, not the whole line.
struct GrammarNarrowingTests {
    @Test(arguments: ["circle pricing", "box pricing", "point at pricing", "highlight pricing", "number pricing",
                      "label pricing as new"])
    func marksThePhraseInsideALongerLine(_ instruction: String) {
        #expect(Footer.picks(instruction) == [Footer.part("Pricing")], "\(instruction)")
    }

    @Test func narrowsAPhraseOfSeveralWords() {
        #expect(Footer.picks("circle sign out") == [Footer.part("Sign out")])
    }

    @Test func narrowsAfterDroppingAUINoun() {
        #expect(Footer.picks("box the sign out link") == [Footer.part("Sign out")])
    }

    @Test func aLabelReferringBackKeepsThePhrase() {
        let operations = GrammarInterpreter.interpret(InterpretRequest(instruction: "circle docs and label it new",
                                                                       targets: [Footer.line])).interpretation?.operations
        #expect(operations?.map(\.picks) == [[Footer.part("Docs")], [Footer.part("Docs")]])
    }

    @Test func blurStillCoversTheWholeLine() {
        #expect(Footer.picks("blur pricing") == [.id(Footer.line.id)])
    }

    @Test func aWholeLineMatchStaysTheWholeTarget() {
        #expect(GrammarInterpreter.interpret(InterpretRequest(instruction: "circle pricing", targets: Screen.targets))
            .interpretation?.operations.first?.picks == [.id(Screen.pricing.id)])
    }

    @Test func aPhraseTwiceInOneLineTakesTheWholeLine() {
        let twice = [Footer.twice]
        let picks = GrammarInterpreter.interpret(InterpretRequest(instruction: "highlight docs", targets: twice))
            .interpretation?.operations.flatMap(\.picks)
        #expect(picks == [.id(Footer.twice.id)])
    }

    @Test func thePartResolvesToItsLineAndItsOwnBox() throws {
        let pick = Footer.part("Pricing")
        #expect(pick.targets(in: Footer.targets) == [Footer.line])
        let part = try #require(pick.part(in: Footer.targets))
        #expect(part.text == "Pricing")
        #expect(part.rect == PixelRect(x: 100, y: 500, width: 70, height: 14))
        let entry = InterpretedOperation(mark: .circle, picks: [pick]).applyEntry(in: Footer.targets)
        #expect(entry.rect == [part.rect])
    }

    @Test func wordRangesLineUpWithTheWords() throws {
        let text = "Kenji's notes: ship v1.2, then rest."
        let ranges = try #require(Words.ranges(in: text))
        #expect(ranges.map { (text as NSString).substring(with: $0) } == ["Kenji", "notes", "ship", "v1.2", "then",
                                                                          "rest"])
        #expect(Words.of(text) == ["kenji", "notes", "ship", "v1.2", "then", "rest"])
    }
}
