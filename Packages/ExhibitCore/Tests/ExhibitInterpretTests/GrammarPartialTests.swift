import ExhibitCore
@testable import ExhibitInterpret
import Foundation
import Testing

/// Issue 42: with no model, a plain name the screen does not show is reported as not found beside what was done.
struct GrammarPartialTests {
    private func noModel(_ instruction: String) -> InterpretOutcome {
        GrammarInterpreter.interpret(InterpretRequest(instruction: instruction, targets: Screen.targets),
                                     unknownNames: .reportNotFound)
    }

    private func isDeclined(_ outcome: InterpretOutcome) -> Bool {
        if case .declined = outcome { return true }
        return false
    }

    @Test func appliesTheRestAndReportsAnUnknownName() {
        #expect(noModel("blur the emails and circle the logout button") == .understood(Interpretation(
            operations: [InterpretedOperation(mark: .blur, picks: [.kind(.email)])],
            notFound: ["logout button"])))
    }

    @Test func reportsAnUnknownPartOfAList() {
        let outcome = noModel("circle pricing and the export button")
        #expect(outcome.interpretation?.operations == [InterpretedOperation(mark: .circle,
                                                                            picks: [.id(Screen.pricing.id)])])
        #expect(outcome.interpretation?.notFound == ["export button"])
    }

    @Test func keepsDecliningWhenAModelCanTry() {
        // The default, and what `say` and dictation use when a model is set up: the model may know the name.
        #expect(isDeclined(Screen.interpret("blur the emails and circle the logout button")))
        #expect(isDeclined(GrammarInterpreter.interpret(
            InterpretRequest(instruction: "blur the emails and circle the logout button", targets: Screen.targets),
            unknownNames: .decline)))
    }

    @Test func declinesAnUnknownBlur() {
        // A redaction that cannot be placed must not look done, even beside one that can.
        #expect(isDeclined(noModel("circle pricing and blur the customer name")))
        #expect(isDeclined(noModel("blur the emails and the customer name")))
    }

    @Test func declinesWhenNothingElseWasUnderstood() {
        #expect(isDeclined(noModel("circle the export button")))
    }

    @Test func declinesDescriptionsAndUnknownInstructions() {
        #expect(isDeclined(noModel("circle pricing and highlight the biggest customer")))
        #expect(isDeclined(noModel("circle pricing and box the link in the footer")))
        #expect(isDeclined(noModel("circle pricing and make it bigger")))
        #expect(isDeclined(noModel("circle pricing and box the first row of the second table")))
    }

    @Test func stillDeclinesJudgementAndQualifiedKinds() {
        #expect(isDeclined(noModel("circle pricing and hide anything personal")))
        #expect(isDeclined(noModel("circle pricing and blur her email")))
    }

    @Test func keepsLabelSplitting() {
        // "label pricing new" still finds the line before the words, rather than reporting "pricing new".
        let outcome = noModel("label pricing new")
        #expect(outcome.interpretation?.operations == [InterpretedOperation(mark: .text,
                                                                            picks: [.id(Screen.pricing.id)],
                                                                            label: "new")])
        #expect(outcome.interpretation?.notFound == [])
    }

    @Test func plainNames() {
        #expect(GrammarParser.isPlainName(["log", "out", "button"]))
        #expect(GrammarParser.isPlainName(["export"]))
        #expect(!GrammarParser.isPlainName(["biggest", "customer"]))
        #expect(!GrammarParser.isPlainName(["make", "it", "bigger"]))
        #expect(!GrammarParser.isPlainName(["a", "very", "long", "name", "here"]))
    }
}
