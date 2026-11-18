import ExhibitCore
@testable import ExhibitInterpret
import Foundation
import Testing

extension Screen {
    static func interpret(_ instruction: String, pointer: PixelPoint? = nil) -> InterpretOutcome {
        GrammarInterpreter.interpret(InterpretRequest(instruction: instruction, targets: targets, pointer: pointer))
    }
}

struct GrammarTests {
    @Test func blursEveryTargetOfAKind() {
        let outcome = Screen.interpret("Blur the emails")
        #expect(outcome == .understood(Interpretation(operations: [
            InterpretedOperation(mark: .blur, picks: [.kind(.email)])
        ])))
    }

    @Test func splitsClausesAtAndBeforeAVerb() {
        let outcome = Screen.interpret("Circle Pricing and point at Sign up")
        #expect(outcome.interpretation?.operations == [
            InterpretedOperation(mark: .circle, picks: [.id(Screen.pricing.id)]),
            InterpretedOperation(mark: .arrow, picks: [.id(Screen.signUp.id)])
        ])
    }

    @Test func prefersAWholeLineOverLinesThatContainTheWord() {
        let ops = Screen.interpret("circle pricing").interpretation?.operations
        #expect(ops?.first?.picks == [.id(Screen.pricing.id)])
    }

    @Test func toleratesAMisheardWord() {
        let ops = Screen.interpret("circle prising").interpretation?.operations
        #expect(ops?.first?.picks == [.id(Screen.pricing.id)])
    }

    @Test func readsPluralKinds() {
        #expect(Screen.interpret("blur all the email addresses").interpretation?.operations.first?.picks
                == [.kind(.email)])
    }

    @Test func joinsASpelledOutEmail() {
        #expect(Screen.interpret("blur the e mails").interpretation?.operations.first?.picks == [.kind(.email)])
    }

    @Test func usesThePointerForThis() {
        let pointer = PixelPoint(x: 610, y: 405)
        let ops = Screen.interpret("highlight this", pointer: pointer).interpretation?.operations
        #expect(ops == [InterpretedOperation(mark: .highlight, picks: [.id(Screen.reply.id)])])
    }

    @Test func pointerPrefersTheSecretOverItsLine() {
        let ops = Screen.interpret("blur this", pointer: PixelPoint(x: 400, y: 305)).interpretation?.operations
        #expect(ops?.first?.picks == [.id(Screen.email.id)])
    }

    @Test func declinesThisWithoutAPointer() {
        guard case .declined = Screen.interpret("blur this") else { Issue.record("expected a decline"); return }
    }

    @Test func reportsAKindTheScreenHasNoneOf() {
        #expect(Screen.interpret("blur the faces") == .understood(Interpretation(operations: [], notFound: ["faces"])))
    }

    @Test(arguments: ["hide anything that identifies the customer", "box the commit that fixed the bug",
                      "circle the export button", "highlight the most popular plan", "arrow to archive",
                      "the emails, blur them"])
    func declinesWhatItCannotBeSureOf(_ instruction: String) {
        guard case .declined = Screen.interpret(instruction) else {
            Issue.record("expected \"\(instruction)\" to be declined")
            return
        }
    }

    @Test func breaksATieByNearnessToTheRestOfTheList() {
        let ops = Screen.interpret("number reply forward and archive").interpretation?.operations
        #expect(ops == [InterpretedOperation(mark: .step, picks: [.id(Screen.reply.id), .id(Screen.forward.id),
                                                                   .id(Screen.archiveButton.id)])])
    }

    @Test func readsSpokenStepNumbers() {
        let ops = Screen.interpret("step one reply step two forward").interpretation?.operations
        #expect(ops?.first?.picks == [.id(Screen.reply.id), .id(Screen.forward.id)])
    }

    @Test func attachesALabelToThePreviousArrow() {
        let ops = Screen.interpret("point at open tickets and label it needs triage").interpretation?.operations
        #expect(ops == [InterpretedOperation(mark: .arrow, picks: [.id(Screen.openTickets.id)], label: "needs triage")])
    }

    @Test(arguments: ["point it open tickets", "appointed open tickets", "pointed at open tickets",
                      "point it at open tickets"])
    func readsMisheardPointAt(_ instruction: String) {
        let ops = Screen.interpret(instruction).interpretation?.operations
        #expect(ops == [InterpretedOperation(mark: .arrow, picks: [.id(Screen.openTickets.id)])], "\(instruction)")
    }

    @Test func readsAMisheardPointAtFollowedByALabel() {
        let ops = Screen.interpret("Point it open tickets and label it needs triage").interpretation?.operations
        #expect(ops == [InterpretedOperation(mark: .arrow, picks: [.id(Screen.openTickets.id)], label: "needs triage")])
    }

    @Test func readsLabels() {
        let asLabel = Screen.interpret("label total as checked").interpretation?.operations
        #expect(asLabel == [InterpretedOperation(mark: .text, picks: [.id(Screen.total.id)], label: "checked")])
        let saying = Screen.interpret("add a label saying check this next to reply").interpretation?.operations
        #expect(saying == [InterpretedOperation(mark: .text, picks: [.id(Screen.reply.id)], label: "check this")])
    }

    @Test func blurPrefersTheValueAndOtherMarksPreferTheLabel() {
        let screen = [Screen.line("Email", 10, 10), Screen.emailLine, Screen.email]
        let blur = GrammarInterpreter.interpret(InterpretRequest(instruction: "blur the email", targets: screen))
        #expect(blur.interpretation?.operations.first?.picks == [.kind(.email)])
        let circle = GrammarInterpreter.interpret(InterpretRequest(instruction: "circle email", targets: screen))
        #expect(circle.interpretation?.operations.first?.picks == [.id(screen[0].id)])
    }

    @Test func keepsWhatItFoundAndReportsAMissingKind() {
        let outcome = Screen.interpret("circle pricing and blur the card numbers")
        #expect(outcome.interpretation == Interpretation(
            operations: [InterpretedOperation(mark: .circle, picks: [.id(Screen.pricing.id)])],
            notFound: ["card numbers"]))
    }

    @Test func chainFallsThroughDeclines() async throws {
        struct Fixed: Interpreter {
            var name: String { "fixed" }
            func interpret(_ request: InterpretRequest) async throws -> InterpretOutcome {
                .understood(Interpretation(operations: [], notFound: ["x"]))
            }
        }
        let chain = ChainedInterpreter([GrammarInterpreter(), Fixed()])
        #expect(chain.name == "grammar+fixed")
        let request = InterpretRequest(instruction: "hide anything personal", targets: Screen.targets)
        #expect(try await chain.interpret(request) == .understood(Interpretation(operations: [], notFound: ["x"])))
        let understood = InterpretRequest(instruction: "blur the keys", targets: Screen.targets)
        #expect(try await chain.interpret(understood).interpretation?.operations.first?.picks == [.kind(.key)])
    }
}
