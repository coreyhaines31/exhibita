import ExhibitCore
@testable import ExhibitEditor
import ExhibitInterpret
import Foundation
import Testing

/// Typed and spoken instructions through the grammar, then a fake model: what is marked, what is said, and that one
/// instruction runs at a time.
@MainActor
@Suite(.timeLimit(.minutes(1))) struct DictationInterpretingTests {
    let fixture = EditorFixture()

    // MARK: - Grammar, then a model

    @Test func whatTheGrammarDeclinesNeedsAModelWhenNoneIsSetUp() async {
        let dictation = dictationSession(fixture)
        dictation.submit("hide anything that identifies the customer")
        await dictation.settle()
        #expect(dictation.editor.dictation == .needsModel(transcript: "hide anything that identifies the customer"))
        #expect(dictation.editor.dictation?.link == .modelSettings)
        #expect(dictation.editor.status.text?.contains("blur the emails") == true, "an example the grammar reads")
        #expect(dictation.editor.marks.isEmpty)
    }

    @Test func theModelIsAskedOnlyWhenTheGrammarDeclines() async {
        let answer = Interpretation(operations: [InterpretedOperation(mark: .blur, picks: [.id(fixture.emailID)])])
        let model = FakeModel(.success(.understood(answer)))
        let dictation = dictationSession(fixture, model: model)
        dictation.submit("blur the emails")
        await dictation.settle()
        #expect(model.calls == 0)
        dictation.submit("hide anything that identifies the customer")
        await dictation.settle()
        #expect(model.calls == 1)
        guard case .applied(_, let summary, true) = dictation.editor.dictation else {
            Issue.record("not applied by the model: \(String(describing: dictation.editor.dictation))")
            return
        }
        #expect(summary == "Blurred 1 email.")
        #expect(dictation.editor.status.text?.contains("⌘Z undoes all of it") == true)
    }

    @Test func aFailingModelChangesNothing() async {
        let model = FakeModel(.failure(.unreachable("connection refused")))
        let dictation = dictationSession(fixture, model: model)
        dictation.submit("hide anything personal")
        await dictation.settle()
        #expect(dictation.editor.dictation == .modelFailed(transcript: "hide anything personal",
                                                           reason: "The local model isn't answering. Is it running?"))
        #expect(dictation.editor.marks.isEmpty)
    }

    @Test func noSuccessBeforeMarksAndASecondInstructionIsRefusedWhileTheModelWorks() async {
        let gate = Gate()
        let answer = Interpretation(operations: [InterpretedOperation(mark: .circle, picks: [.id(fixture.updateID)])])
        let model = FakeModel(.success(.understood(answer)), gate: gate)
        let speech = FakeTranscriber()
        let dictation = dictationSession(fixture, speech, model: model)
        dictation.submit("point out the main action")
        await until { model.calls == 1 }
        #expect(dictation.editor.dictation == .interpreting(transcript: "point out the main action", usingModel: true))
        #expect(dictation.editor.marks.isEmpty)

        dictation.press()
        #expect(speech.prepareCalls == 0)
        #expect(dictation.editor.status == .notice(DictationSession.busyMessage))
        dictation.submit("blur the emails")
        dictation.beginTyping()
        #expect(!dictation.isTyping)

        gate.open()
        await dictation.settle()
        #expect(dictation.editor.marks.map(\.kind) == [.circle], "only the first instruction, never interleaved")
        #expect(dictation.editor.dictation?.changedMarks == true)
    }

    @Test func closingWhileTheModelWorksDropsTheAnswer() async {
        let gate = Gate()
        let answer = Interpretation(operations: [InterpretedOperation(mark: .circle, picks: [.id(fixture.updateID)])])
        let model = FakeModel(.success(.understood(answer)), gate: gate)
        let dictation = dictationSession(fixture, model: model)
        dictation.submit("point out the main action")
        await until { model.calls == 1 }
        dictation.close()
        gate.open()
        await dictation.settle()
        #expect(dictation.editor.marks.isEmpty)
    }

    // MARK: - What was not found

    @Test func partialMatchMarksWhatWasFoundAndNamesTheRest() async {
        let dictation = dictationSession(fixture)
        dictation.submit("blur the emails and the card numbers")
        await dictation.settle()
        guard case .partial(_, let summary, _) = dictation.editor.dictation else {
            Issue.record("not partial: \(String(describing: dictation.editor.dictation))")
            return
        }
        #expect(summary.hasPrefix("Blurred 1 email."))
        #expect(summary.contains("Couldn't find: "))
        #expect(dictation.editor.marks.map(\.kind) == [.blur])
    }

    @Test func anUnknownNameWithoutAModelIsNamedBesideWhatWasDone() async {
        let dictation = dictationSession(fixture)
        dictation.submit("blur the emails and circle the logout button")
        await dictation.settle()
        guard case .partial(_, let summary, false) = dictation.editor.dictation else {
            Issue.record("not partial: \(String(describing: dictation.editor.dictation))")
            return
        }
        #expect(summary == "Blurred 1 email. Couldn't find: logout button.")
        #expect(dictation.editor.marks.map(\.kind) == [.blur])
    }

    @Test func anUnknownNameGoesToTheModelWhenOneIsSetUp() async {
        let answer = Interpretation(operations: [InterpretedOperation(mark: .blur, picks: [.id(fixture.emailID)])])
        let model = FakeModel(.success(.understood(answer)))
        let dictation = dictationSession(fixture, model: model)
        dictation.submit("blur the emails and circle the logout button")
        await dictation.settle()
        #expect(model.calls == 1)
    }

    @Test func nothingFoundChangesNothing() async {
        let dictation = dictationSession(fixture)
        dictation.submit("blur the faces")
        await dictation.settle()
        guard case .nothingFound(_, let summary) = dictation.editor.dictation else {
            Issue.record("not nothing found: \(String(describing: dictation.editor.dictation))")
            return
        }
        #expect(summary.hasPrefix("Couldn't find: "))
        #expect(dictation.editor.status.text?.hasSuffix("No changes made.") == true)
        #expect(dictation.editor.marks.isEmpty)
    }

    @Test func aBlurIsNeverNarrowedWhateverTheModelSays() async {
        let narrow = Interpretation(operations: [
            InterpretedOperation(mark: .blur, picks: [.part(fixture.renewsID, start: 0, length: 6)])
        ])
        let dictation = dictationSession(fixture, model: FakeModel(.success(.understood(narrow))))
        dictation.submit("hide the start of the renewal line")
        await dictation.settle()
        let blur = dictation.editor.marks.first
        #expect(blur?.bounds.covers(fixture["renews"]) == true)
    }

    // MARK: - Typed instructions

    @Test func aTypedInstructionTakesTheSamePath() async {
        let dictation = dictationSession(fixture)
        dictation.beginTyping()
        #expect(dictation.isTyping)
        dictation.submit("  ")
        #expect(!dictation.isTyping)
        #expect(dictation.editor.dictation == nil)
        dictation.submit("circle renews", pointer: nil)
        await dictation.settle()
        #expect(dictation.editor.marks.map(\.kind) == [.circle])
    }
}
