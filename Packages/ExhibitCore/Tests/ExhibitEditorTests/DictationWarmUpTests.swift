import ExhibitCore
@testable import ExhibitEditor
import ExhibitInterpret
import Foundation
import Testing

/// When the editor has the model read the screen ahead of an instruction: as D goes down or the typed field opens,
/// only with a model that can be warmed up, never holding up the grammar.
@MainActor
@Suite(.timeLimit(.minutes(1))) struct DictationWarmUpTests {
    let fixture = EditorFixture()

    func session(_ model: (any Interpreter)?, transcriber: FakeTranscriber? = FakeTranscriber(),
                 targetsLoaded: Bool = true) -> DictationSession {
        DictationSession(editor: makeEditor(fixture, targetsLoaded: targetsLoaded), original: fixture.fixture.image,
                         transcriber: transcriber, model: { model })
    }

    static let answer = Interpretation(operations: [])

    @Test func holdingDWarmsUpTheModelWithTheScreensTargets() async {
        let model = WarmingFakeModel(.success(.understood(Self.answer)))
        let dictation = session(model)
        dictation.press()
        #expect(model.warmUps == [dictation.editor.document.targets])
        #expect(model.calls == 0, "warming up is not an instruction")
        dictation.release()
        await dictation.settle()
    }

    @Test func openingTheTypedFieldWarmsUpTheModel() {
        let model = WarmingFakeModel(.success(.understood(Self.answer)))
        let dictation = session(model)
        dictation.beginTyping()
        #expect(model.warmUps.count == 1)
        #expect(model.warmUps.first == dictation.editor.document.targets)
    }

    @Test func nothingIsWarmedBeforeTheTextIsRead() {
        let model = WarmingFakeModel(.success(.understood(Self.answer)))
        let dictation = session(model, targetsLoaded: false)
        dictation.press()
        dictation.beginTyping()
        #expect(model.warmUps.isEmpty)
    }

    @Test func nothingIsWarmedWithoutSpeechOrWhileBusy() async {
        let model = WarmingFakeModel(.success(.understood(Self.answer)))
        session(model, transcriber: nil).press()
        #expect(model.warmUps.isEmpty, "no speech means no instruction is coming")

        let gate = Gate()
        let slow = WarmingFakeModel(.success(.understood(Self.answer)), gate: gate)
        let dictation = session(slow)
        dictation.submit("hide anything that identifies the customer")
        await until { slow.calls == 1 }
        dictation.press()
        dictation.beginTyping()
        #expect(slow.warmUps.isEmpty, "a refused instruction warms nothing")
        gate.open()
        await dictation.settle()
    }

    @Test func aModelThatCannotWarmUpIsLeftAlone() async {
        let model = FakeModel(.success(.understood(Self.answer)))
        let dictation = session(model)
        dictation.beginTyping()
        dictation.submit("hide anything that identifies the customer")
        await dictation.settle()
        #expect(model.calls == 1)
    }

    /// A lazily found model is not looked for on D: only an instruction the grammar declines starts the lookup.
    @Test func aLazyModelIsNotLookedForToWarmUp() async {
        let lookups = Counter()
        let lazy = LazyModelInterpreter {
            await lookups.increment()
            return nil
        }
        let dictation = session(lazy)
        dictation.beginTyping()
        dictation.submit("blur the emails")
        await dictation.settle()
        #expect(await lookups.value == 0)
    }

    @Test func theGrammarAnswersWithoutTheModelAfterAWarmUp() async {
        let model = WarmingFakeModel(.success(.understood(Self.answer)))
        let dictation = session(model)
        dictation.beginTyping()
        dictation.submit("blur the emails")
        await dictation.settle()
        #expect(model.warmUps.count == 1)
        #expect(model.calls == 0, "the warm-up was left unused")
        #expect(dictation.editor.marks.count == 1)
    }

    // MARK: - When the editor opens

    @Test func openingAnEditorAsksForAWarmUpOnlyIfTheModelIsLoaded() {
        let model = WarmingFakeModel(.success(.understood(Self.answer)))
        let dictation = session(model)
        dictation.editorOpened()
        #expect(model.warmUpsIfLoaded == [dictation.editor.document.targets])
        #expect(model.warmUps.isEmpty, "opening never loads a model")
    }

    @Test func openingWaitsForTheTextToBeRead() async {
        let model = WarmingFakeModel(.success(.understood(Self.answer)))
        let dictation = session(model, targetsLoaded: false)
        dictation.editorOpened()
        #expect(model.warmUpsIfLoaded.isEmpty)
        dictation.editor.owner.mergeTargets(fixture.document.targets)
        await until { model.warmUpsIfLoaded.count == 1 }
        #expect(model.warmUpsIfLoaded.first == fixture.document.targets)
    }

    @Test func aClosedEditorWarmsNothingWhenItsTextArrives() async throws {
        let model = WarmingFakeModel(.success(.understood(Self.answer)))
        let dictation = session(model, targetsLoaded: false)
        dictation.editorOpened()
        dictation.close()
        dictation.editor.owner.mergeTargets(fixture.document.targets)
        try await Task.sleep(for: .milliseconds(50))
        #expect(model.warmUpsIfLoaded.isEmpty)
    }

    @Test func openingWithNoWarmableModelDoesNothing() async {
        let lookups = Counter()
        let lazy = LazyModelInterpreter {
            await lookups.increment()
            return nil
        }
        session(lazy).editorOpened()
        session(nil).editorOpened()
        #expect(await lookups.value == 0)
    }
}
