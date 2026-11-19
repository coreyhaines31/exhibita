import ExhibitCore
import ExhibitFixtures
@testable import ExhibitTargets
import Foundation
import Testing

/// Swaps Latin letters and digits for look-alikes from other scripts, the way OCR sometimes reads them.
private func lookalike(_ text: String) -> String {
    let swaps: [Character: Character] = [
        "A": "А", "B": "В", "C": "С", "E": "Е", "H": "Н", "K": "К", "M": "М", "O": "О", "P": "Р", "T": "Т", "X": "Х",
        "a": "а", "c": "с", "e": "е", "o": "о", "p": "р", "x": "х", "y": "у", "0": "Ø", "N": "Ν", "Z": "Ζ", "v": "ν",
        "1": "１", "4": "４", "-": "\u{2212}"
    ]
    return String(text.map { swaps[$0] ?? $0 })
}

private func summary(_ text: String) -> [String] {
    SensitivePatterns.matches(in: text).map { "\($0.kind.rawValue) \($0.range.location) \($0.range.length)" }
}

@Suite struct LookalikeTests {
    static let lines: [String] = [
        "token \(FakeKeys.github) here", "token \(FakeKeys.stripe) here", "token \(FakeKeys.aws) here",
        "token \(FakeKeys.anthropic) here", "token \(FakeKeys.slack) here", "-----BEGIN RSA " + "PRIVATE KEY-----",
        "API key \(FakeKeys.generic)", "hash \(FakeKeys.hex) done", "export API_TOKEN=tk_" + "Zx81LmQ02vBn77PqRsT4uVw9",
        "postgres://app:" + "hunter2hunter" + "@db.example.com/main", "Password: " + "s3cr3t" + "value99",
        "Contact \(FixtureValues.email) today", "Card \(FakeKeys.visa) exp", "Call \(FixtureValues.phone) now"
    ]

    @Test(arguments: lines)
    func lookalikesFindTheSameThingsInTheSamePlaces(line: String) {
        let swapped = lookalike(line)
        #expect(swapped != line)
        #expect(swapped.utf16.count == line.utf16.count)
        #expect(!summary(line).isEmpty, "\(line)")
        #expect(summary(swapped) == summary(line), "\(swapped)")
    }

    @Test func theMisreadFromIssue20IsAKey() {
        // As Vision returned it: Cyrillic А and В, and Ø for 0.
        let read = "export АPI_TOKEN=tk_Zx81LmQØ2vВn77PqRsT4uVw9"
        let matches = SensitivePatterns.matches(in: read)
        #expect(matches.map(\.kind) == [.key])
        #expect(matches.first.map { (read as NSString).substring(with: $0.range).hasPrefix("tk_") } == true)
    }

    @Test func storedLineTextIsFoldedAndMasked() {
        let targets = TargetFinder.lineTargets(text: "Астe export АPI_TOKEN=tk_Zx81LmQØ2vВn77PqRsT4uVw9",
                                               rect: PixelRect(x: 0, y: 0, width: 400, height: 20), confidence: 1,
                                               spans: nil)
        let line = targets.first?.text ?? ""
        #expect(line.hasPrefix("Acme export API_TOKEN="))
        #expect(!line.contains("Zx81"))
        #expect(targets.map(\.kind) == [.text, .key])
    }
}
