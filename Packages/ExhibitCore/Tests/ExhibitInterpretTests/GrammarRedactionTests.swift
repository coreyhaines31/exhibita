import ExhibitCore
@testable import ExhibitInterpret
import Foundation
import Testing

/// A chat screen where a name appears on its own, inside longer lines and wrapped across two lines.
private enum Chat {
    static let sidebar = Screen.line("Kenji Watanabe", 20, 100, width: 120)
    static let headerOne = Screen.line("Kenji Watanabe 10:02 AM", 300, 100, width: 200)
    static let message = Screen.line("Thanks, I will ask Kenji", 300, 130, width: 200)
    static let wrapped = Screen.line("Watanabe about the deploy window", 300, 146, width: 260)
    static let headerTwo = Screen.line("Kenji Watanabe 10:15 AM", 300, 200, width: 200)
    static let other = Screen.line("Mei Chen", 20, 130, width: 120)
    static let samantha = Screen.line("Samantha Ortiz", 20, 160, width: 120)

    static let targets = [sidebar, headerOne, message, wrapped, other, samantha, headerTwo]

    static func interpret(_ instruction: String) -> InterpretOutcome {
        GrammarInterpreter.interpret(InterpretRequest(instruction: instruction, targets: targets))
    }

    static func picked(_ instruction: String) -> Set<UUID>? {
        guard let operations = interpret(instruction).interpretation?.operations else { return nil }
        return Set(operations.flatMap { $0.targetIDs(in: targets) })
    }
}

/// When a redaction is ambiguous, the grammar declines or covers too much. It never quietly covers too little.
struct GrammarRedactionTests {
    @Test func blurTakesEveryLineHoldingTheName() {
        let picked = Chat.picked("blur kenji watanabe")
        #expect(picked == Set([Chat.sidebar, Chat.headerOne, Chat.headerTwo, Chat.message, Chat.wrapped].map(\.id)))
    }

    @Test func blurTakesBothHalvesOfAWrappedName() {
        let picked = Chat.picked("blur kenji watanabe") ?? []
        #expect(picked.contains(Chat.message.id))
        #expect(picked.contains(Chat.wrapped.id))
        #expect(!picked.contains(Chat.other.id))
    }

    @Test func highlightTakesEveryLineHoldingThePhrase() {
        let picked = Chat.picked("highlight kenji watanabe")
        #expect(picked?.isSuperset(of: [Chat.sidebar.id, Chat.headerOne.id, Chat.headerTwo.id]) == true)
    }

    @Test func blurTakesAPhraseInsideALongerWord() {
        #expect(Chat.picked("blur sam") == [Chat.samantha.id])
    }

    @Test func aMisheardNameStillBlursEveryLineWithIt() {
        let picked = Chat.picked("blur kenji wadanabi") ?? []
        #expect(picked.isSuperset(of: [Chat.sidebar.id, Chat.headerOne.id, Chat.headerTwo.id]))
    }

    @Test func otherMarksStillPreferTheWholeLine() {
        let picked = Chat.picked("circle kenji watanabe")
        #expect(picked == [Chat.sidebar.id])
    }

    @Test func declinesTwoEquallyCloseMishearingsForABlur() {
        let screen = [Screen.line("Sign in", 10, 10), Screen.line("Sign on", 10, 40)]
        let outcome = GrammarInterpreter.interpret(InterpretRequest(instruction: "blur sign un", targets: screen))
        guard case .declined = outcome else { Issue.record("expected a decline, got \(outcome)"); return }
    }

    /// The principle, over every phrase on the chat screen: whatever a blur picks covers every line that holds
    /// the phrase, or the grammar declines.
    @Test(arguments: ["kenji", "watanabe", "kenji watanabe", "mei chen", "deploy window", "samantha"])
    func aBlurNeverCoversLessThanEveryLineWithThePhrase(_ phrase: String) {
        let holding = Set(Chat.targets.filter { target in
            (target.text ?? "").lowercased().contains(phrase)
        }.map(\.id))
        let outcome = Chat.interpret("blur \(phrase)")
        guard let operations = outcome.interpretation?.operations else { return }
        let picked = Set(operations.flatMap { $0.targetIDs(in: Chat.targets) })
        #expect(picked.isSuperset(of: holding), "\(phrase)")
    }
}
