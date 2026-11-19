import ExhibitCore
@testable import ExhibitEditor
import ExhibitInterpret
import ExhibitShell
import Foundation
import Testing

/// Push-to-talk and typed instructions with a fake transcriber and fake models: no microphone, no speech framework,
/// no network.
@MainActor
@Suite(.timeLimit(.minutes(1))) struct DictationSessionTests {
    let fixture = EditorFixture()

    // MARK: - Hold D, speak, release

    @Test func holdSpeakReleaseMarksAndOneUndoRemovesTheBatch() async {
        let speech = FakeTranscriber()
        let dictation = dictationSession(fixture, speech)
        dictation.press()
        await until { dictation.isListening }
        #expect(dictation.editor.status == .dictation(.listening(transcript: "")))
        speech.hear("blur the emails and")
        #expect(dictation.editor.dictation == .listening(transcript: "blur the emails and"))
        speech.final = "blur the emails and circle update plan"
        dictation.release()
        await dictation.settle()

        guard case .applied(_, let summary, let byModel) = dictation.editor.dictation else {
            Issue.record("not applied: \(String(describing: dictation.editor.dictation))")
            return
        }
        #expect(!byModel)
        #expect(summary.hasPrefix("Blurred 1 email, circled \"Update plan\""))
        #expect(dictation.editor.marks.map(\.kind) == [.blur, .circle])
        #expect(dictation.editor.marks.first?.targetID == fixture.emailID)
        dictation.editor.undo()
        #expect(dictation.editor.marks.isEmpty)
        #expect(dictation.lastReleaseToMarks != nil)
    }

    @Test func releasingWithNothingSaidDoesNothing() async {
        let speech = FakeTranscriber()
        let dictation = dictationSession(fixture, speech)
        dictation.press()
        await until { dictation.isListening }
        dictation.release()
        await dictation.settle()
        #expect(dictation.editor.dictation == nil)
        #expect(dictation.editor.marks.isEmpty)
        #expect(!dictation.editor.canUndo)
        #expect(!dictation.isBusy)
    }

    @Test func keyRepeatsAndASecondPressAreIgnored() async {
        let speech = FakeTranscriber()
        let dictation = dictationSession(fixture, speech)
        dictation.press()
        dictation.press()
        await until { dictation.isListening }
        dictation.press()
        #expect(speech.prepareCalls == 1)
        #expect(speech.startCalls == 1)
        #expect(speech.hints == ["Renews on December 1, 2026", "Update plan"], "screen words, never masked secrets")
    }

    @Test func escWhileListeningCancelsAndChangesNothing() async {
        let speech = FakeTranscriber()
        let dictation = dictationSession(fixture, speech)
        dictation.press()
        await until { dictation.isListening }
        speech.hear("blur the emails")
        #expect(dictation.intercept(.escape))
        #expect(speech.cancelCalls == 1)
        speech.final = "blur the emails"
        dictation.release()
        await dictation.settle()
        #expect(dictation.editor.marks.isEmpty)
        #expect(dictation.editor.status == .notice("Dictation cancelled"))
        #expect(speech.finishCalls == 0)
    }

    @Test func escIsLeftToTheEditorWhenNotListening() {
        let dictation = dictationSession(fixture)
        #expect(!dictation.intercept(.escape))
        #expect(!dictation.intercept(.character("d")))
    }

    @Test func thePointerAtKeyDownAnswersThis() async {
        let speech = FakeTranscriber()
        let dictation = dictationSession(fixture, speech)
        dictation.editor.hoverPoint = fixture.point(in: fixture["update"])
        dictation.press()
        await until { dictation.isListening }
        dictation.editor.hoverPoint = nil
        speech.final = "highlight this"
        dictation.release()
        await dictation.settle()
        #expect(dictation.editor.marks.map(\.kind) == [.highlight])
        #expect(dictation.editor.marks.first?.targetID == fixture.updateID)
    }

    @Test func releasedWhileMacOSAsksForPermissionWaitsForTheNextPress() async {
        let speech = FakeTranscriber()
        speech.prepareGate = Gate()
        let dictation = dictationSession(fixture, speech)
        dictation.press()
        #expect(dictation.editor.dictation == .preparing)
        dictation.release()
        speech.prepareGate.open()
        await dictation.settle()
        #expect(speech.startCalls == 0)
        #expect(dictation.editor.status == .notice("Ready. Hold D and speak."))
        #expect(!dictation.isBusy)
    }

    // MARK: - Permission and availability

    @Test func microphoneDeniedSaysSoAndHandToolsStillWork() async {
        let speech = FakeTranscriber()
        speech.readiness = .microphoneDenied
        let dictation = dictationSession(fixture, speech)
        dictation.press()
        await dictation.settle()
        #expect(dictation.editor.dictation == .microphoneDenied)
        #expect(dictation.editor.dictation?.link == .microphoneSettings)
        #expect(speech.startCalls == 0)
        _ = dictation.editor.handle(.character("b"))
        dictation.editor.click(fixture.point(in: fixture["email"]))
        #expect(dictation.editor.marks.map(\.kind) == [.blur])
        #expect(dictation.editor.dictation == nil, "the next action clears it")
    }

    @Test func noOnDeviceSpeechSaysSoAndOffersTyping() async {
        let speech = FakeTranscriber()
        speech.readiness = .unavailable("On-device speech isn't available for English (United Kingdom).")
        let dictation = dictationSession(fixture, speech)
        dictation.press()
        await dictation.settle()
        #expect(dictation.editor.status.text
            == "On-device speech isn't available for English (United Kingdom). Press / to type instead.")
        let none = dictationSession(fixture, nil)
        none.press()
        #expect(none.editor.dictation == .speechUnavailable(reason: "Speech isn't available on this Mac."))
    }

    @Test func theSpeechModelDownloadsWithProgressThenListens() async {
        let speech = FakeTranscriber()
        speech.readiness = .needsDownload(bytes: 120_000_000)
        speech.downloadGate = Gate()
        let dictation = dictationSession(fixture, speech)
        dictation.press()
        await until { dictation.editor.dictation == .downloading(progress: 0.5, bytes: 120_000_000) }
        #expect(dictation.editor.status.text == "Downloading the speech model, 50% of 120 MB. Esc cancels.")
        speech.downloadGate.open()
        await until { dictation.isListening }
        #expect(speech.downloaded)
    }

    @Test func escCancelsTheDownload() async {
        let speech = FakeTranscriber()
        speech.readiness = .needsDownload(bytes: nil)
        speech.downloadGate = Gate()
        let dictation = dictationSession(fixture, speech)
        dictation.press()
        await until { dictation.editor.dictation == .downloading(progress: 0.5, bytes: nil) }
        #expect(dictation.intercept(.escape))
        speech.downloadGate.open()
        await dictation.settle()
        #expect(dictation.editor.dictation == .downloadStopped(reason: "Download cancelled. Hold D to try again."))
        #expect(speech.startCalls == 0)
        #expect(!dictation.isBusy)
    }

    @Test func notWhileTextIsBeingRead() {
        let speech = FakeTranscriber()
        let dictation = dictationSession(fixture, speech, targetsLoaded: false)
        dictation.press()
        #expect(speech.prepareCalls == 0)
        #expect(dictation.editor.status == .notice("Reading text. Dictate once it finishes."))
    }

}

/// A session over the fixture with a fake transcriber and an optional fake model.
@MainActor
func dictationSession(_ fixture: EditorFixture, _ transcriber: FakeTranscriber? = FakeTranscriber(),
                      model: FakeModel? = nil, targetsLoaded: Bool = true) -> DictationSession {
    let editor = makeEditor(fixture, targetsLoaded: targetsLoaded)
    return DictationSession(editor: editor, original: fixture.fixture.image, transcriber: transcriber,
                            model: { model })
}

/// Lets a session's tasks run until `condition` holds.
@MainActor
func until(_ condition: () -> Bool) async {
    for _ in 0..<500 where !condition() {
        try? await Task.sleep(for: .milliseconds(2))
    }
    #expect(condition())
}
