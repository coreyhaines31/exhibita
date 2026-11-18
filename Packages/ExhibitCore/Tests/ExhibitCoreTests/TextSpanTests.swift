import ExhibitCore
import Foundation
import Testing

@Suite struct TextSpanTests {
    // "See Pricing and plans": four words, each 10 pixels per character, one space of 10 pixels between.
    static let line: Target = {
        let words = ["See", "Pricing", "and", "plans"]
        var spans: [TextSpan] = []
        var offset = 0
        for word in words {
            spans.append(TextSpan(start: offset, length: word.utf16.count,
                                  rect: PixelRect(x: 100 + Double(offset) * 10, y: 50, width: Double(word.count) * 10,
                                                  height: 20)))
            offset += word.utf16.count + 1
        }
        return Target(kind: .text, text: words.joined(separator: " "),
                      rect: PixelRect(x: 100, y: 50, width: 210, height: 20), spans: spans)
    }()

    @Test func aWholeWordGetsItsOwnBox() throws {
        let text = try #require(Self.line.text)
        let range = try #require(text.range(of: "Pricing"))
        #expect(Self.line.rect(for: range) == PixelRect(x: 140, y: 50, width: 70, height: 20))
    }

    @Test func wordsAcrossASpaceAreUnited() throws {
        let range = try #require(Self.line.text?.range(of: "Pricing and"))
        #expect(Self.line.rect(for: range) == PixelRect(x: 140, y: 50, width: 110, height: 20))
    }

    @Test func partOfAWordIsAProportionalSlice() {
        // "ric" is characters 1..<4 of "Pricing".
        let slice = Self.line.rect(forUTF16Range: NSRange(location: 5, length: 3))
        #expect(slice == PixelRect(x: 150, y: 50, width: 30, height: 20))
    }

    @Test func gapsEmptyAndOutOfBoundsRangesHaveNoBox() {
        #expect(Self.line.rect(forUTF16Range: NSRange(location: 3, length: 1)) == nil)
        #expect(Self.line.rect(forUTF16Range: NSRange(location: 4, length: 0)) == nil)
        #expect(Self.line.rect(forUTF16Range: NSRange(location: 20, length: 5)) == nil)
        #expect(Target(kind: .face, rect: Self.line.rect).rect(forUTF16Range: NSRange(location: 0, length: 1)) == nil)
    }

    @Test func withoutSpansTheWholeRectIsOneSpan() {
        let old = Target(kind: .text, text: "abcd", rect: PixelRect(x: 0, y: 0, width: 40, height: 10))
        #expect(old.rect(forUTF16Range: NSRange(location: 2, length: 2)) == PixelRect(x: 20, y: 0, width: 20, height: 10))
    }

    @Test func spansAreOptionalOnDiskAndRoundTrip() throws {
        let old = Data((#"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","kind":"text","text":"Hi","#
                        + #""rect":{"x":1,"y":2,"width":3,"height":4}}"#).utf8)
        let decoded = try JSONDecoder().decode(Target.self, from: old)
        #expect(decoded.spans == nil)
        let encoded = String(bytes: try JSONEncoder().encode(decoded), encoding: .utf8)
        #expect(encoded?.contains("spans") == false)
        let again = try JSONDecoder().decode(Target.self, from: try JSONEncoder().encode(Self.line))
        #expect(again == Self.line)
    }
}
