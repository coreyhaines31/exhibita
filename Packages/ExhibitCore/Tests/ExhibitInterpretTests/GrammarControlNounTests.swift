import ExhibitCore
@testable import ExhibitInterpret
import Foundation
import Testing

/// A terminal line that says "export" and an email, and a toolbar with a real Export button.
private enum Page {
    static let command = Screen.line("jules@build-01 ~/orders % export API_TOKEN=\u{2022}\u{2022}\u{2022}\u{2022}", 20,
                                     140, width: 600)
    static let sentence = Screen.line("You can export the report as a spreadsheet at any time", 20, 180, width: 500)
    static let emailLine = Screen.line("Owner: \u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}", 20, 220, width: 200)
    static let email = Target(kind: .email, rect: PixelRect(x: 80, y: 220, width: 140, height: 14))
    static let exportButton = Screen.line("Export", 900, 40, width: 60)
    static let exportCSV = Screen.line("Export CSV", 900, 40, width: 90)

    static func interpret(_ instruction: String, _ targets: [Target]) -> InterpretOutcome {
        GrammarInterpreter.interpret(InterpretRequest(instruction: instruction, targets: targets),
                                     unknownNames: .reportNotFound)
    }

    static func picks(_ instruction: String, _ targets: [Target]) -> [TargetPick]? {
        interpret(instruction, targets).interpretation?.operations.flatMap(\.picks)
    }
}

/// Issue 48: "circle the export button" must not circle "export" inside a command line.
struct GrammarControlNounTests {
    @Test func aLoneMatchInACodeLineIsNotFound() {
        let targets = [Page.command, Page.emailLine, Page.email]
        #expect(Page.interpret("blur the emails and circle the export button", targets) == .understood(
            Interpretation(operations: [InterpretedOperation(mark: .blur, picks: [.kind(.email)])],
                           notFound: ["export button"])))
    }

    @Test(arguments: ["circle the export button", "box the export button", "point at the export button",
                      "highlight the export button", "circle the export link", "box the export tab"])
    func noPointingMarkTakesAWordInsideCodeOrASentence(_ instruction: String) {
        let outcome = Page.interpret("blur the emails and " + instruction, [Page.command, Page.sentence,
                                                                             Page.emailLine, Page.email])
        #expect(outcome.interpretation?.operations.map(\.mark) == [.blur], "\(instruction)")
        #expect(outcome.interpretation?.notFound == ["export button", "export link", "export tab"]
            .filter { instruction.hasSuffix($0) }, "\(instruction)")
    }

    @Test func aShortControlIsStillChosen() {
        #expect(Page.picks("circle the export button", [Page.exportButton]) == [.id(Page.exportButton.id)])
        let range = ("Export CSV" as NSString).range(of: "Export")
        #expect(Page.picks("circle the export button", [Page.exportCSV])
            == [.part(Page.exportCSV.id, start: range.location, length: range.length)])
    }

    @Test(arguments: ["circle the export button", "box the export button", "point at the export button",
                      "highlight the export button"])
    func theControlWinsOverCodeAndSentences(_ instruction: String) {
        let targets = [Page.command, Page.sentence, Page.exportButton]
        #expect(Page.picks(instruction, targets) == [.id(Page.exportButton.id)], "\(instruction)")
    }

    @Test func withoutAControlNounTheWordIsStillFound() {
        let range = (Page.sentence.text! as NSString).range(of: "export")
        #expect(Page.picks("circle export", [Page.sentence])
            == [.part(Page.sentence.id, start: range.location, length: range.length)])
    }

    @Test func blurIsUnchanged() {
        // A redaction may cover too much but never too little: a blur still takes every line holding the word.
        let targets = [Page.command, Page.sentence, Page.exportButton]
        let all = targets.map { TargetPick.id($0.id) }
        #expect(Page.picks("blur the export button", targets) == all)
        #expect(Page.picks("blur export", targets) == all)
    }

    @Test func codeLooksLikeCode() {
        #expect(GrammarMatcher.looksLikeCode("jules@build-01 ~/orders % export API_TOKEN=abc"))
        #expect(GrammarMatcher.looksLikeCode("const total = sum(rows);"))
        #expect(GrammarMatcher.looksLikeCode("DATABASE_URL"))
        #expect(!GrammarMatcher.looksLikeCode("Export CSV"))
        #expect(!GrammarMatcher.looksLikeCode("99.99% uptime SLA"))
        #expect(!GrammarMatcher.looksLikeCode("Pricing \u{00B7} Docs \u{00B7} Sign out"))
    }
}
