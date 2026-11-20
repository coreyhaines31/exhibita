import CoreGraphics
import ExhibitCore
import ExhibitInterpret
import Foundation
import Observation

/// Push-to-talk and typed instructions for one open capture: hold D, speak, release; or press / and type.
///
/// The grammar reads the instruction first. Only when it declines, and a local model is set up and turned on, is
/// the model asked. A model that can read the screen ahead is warmed up as soon as D goes down or the typed field
/// opens. The result is applied as one undo step through the same planning as `exhibit say`, and the
/// status line says what was done only after the marks exist. One instruction at a time: a second one while the
/// first is still being worked on is refused with a message, never queued behind it or interleaved with it.
@MainActor
@Observable
public final class DictationSession {
    private enum Phase {
        case idle, preparing, downloading, listening, working
    }

    public let editor: CaptureEditor
    /// True while D is held down.
    public private(set) var isHeld = false
    /// True while the typed-instruction field is open.
    public private(set) var isTyping = false
    private var phase: Phase = .idle

    @ObservationIgnored private let original: CGImage
    @ObservationIgnored private let transcriber: (any SpeechTranscribing)?
    @ObservationIgnored private let model: @MainActor () -> (any Interpreter)?
    @ObservationIgnored private var pointer: PixelPoint?
    @ObservationIgnored private var listening: Task<Void, Never>?
    @ObservationIgnored private var working: Task<Void, Never>?
    @ObservationIgnored private var closed = false
    @ObservationIgnored private let clock = ContinuousClock()
    @ObservationIgnored private var releasedAt: ContinuousClock.Instant?
    /// From releasing D (or pressing ↩ in the typed field) to the marks being applied, for the 1.5 s budget.
    @ObservationIgnored public private(set) var lastReleaseToMarks: Duration?

    /// `model` is asked for each instruction, at once, and returns nil when no model is set up or chosen. It
    /// never waits: anything slow to find (the app's `LazyModelInterpreter`) happens only when the grammar
    /// declines, and a model that turns out not to exist (`ModelUnavailable`) reads as "needs a model".
    /// `transcriber` is nil when this Mac has no usable speech at all.
    public init(editor: CaptureEditor, original: CGImage, transcriber: (any SpeechTranscribing)?,
                model: @escaping @MainActor () -> (any Interpreter)? = { nil }) {
        self.editor = editor
        self.original = original
        self.transcriber = transcriber
        self.model = model
    }

    /// Listening, readying speech, or working on an instruction.
    public var isBusy: Bool { phase != .idle }
    public var isListening: Bool { phase == .listening }

    // MARK: - D

    /// D went down. Key repeats and a second press while held are ignored. `pointer` (in image pixels) defaults to
    /// where the pointer is over the capture, so "highlight this" works.
    public func press(pointer: PixelPoint? = nil) {
        guard !closed, !isHeld, !isTyping else { return }
        if phase == .working {
            editor.show(Self.busyMessage)
            return
        }
        guard phase == .idle else { return }
        guard editor.targetsLoaded else {
            editor.show("Reading text. Dictate once it finishes.")
            return
        }
        guard let transcriber else {
            finish(.speechUnavailable(reason: "Speech isn't available on this Mac."))
            return
        }
        editor.commitText()
        warmUpModel()
        isHeld = true
        self.pointer = pointer ?? editor.hoverPoint
        phase = .preparing
        show(.preparing)
        listening = Task { await self.ready(transcriber) }
    }

    /// D came up. With nothing said, nothing happens.
    public func release() {
        guard isHeld else { return }
        isHeld = false
        releasedAt = clock.now
        if phase == .listening, let transcriber {
            listening = Task { await self.stopListening(transcriber) }
        }
        // While readying, `ready` sees the key is up and stops before listening.
    }

    /// A key that dictation takes before the editor: Esc while listening, readying or downloading cancels.
    /// Returns whether it was taken.
    public func intercept(_ key: EditorKey) -> Bool {
        guard key == .escape else { return false }
        switch phase {
        case .preparing, .listening:
            transcriber?.cancel()
            listening?.cancel()
            listening = nil
            isHeld = false
            phase = .idle
            editor.dictation = nil
            editor.show("Dictation cancelled")
            return true
        case .downloading:
            listening?.cancel()
            return true
        case .idle, .working:
            return false
        }
    }

    // MARK: - Typed instructions

    /// Opens the field for typing an instruction instead of saying it.
    public func beginTyping() {
        guard !closed, !isHeld else { return }
        if phase == .working {
            editor.show(Self.busyMessage)
            return
        }
        guard phase == .idle else { return }
        editor.commitText()
        isTyping = true
        warmUpModel()
    }

    public func endTyping() {
        isTyping = false
    }

    /// A typed instruction, through the same path as a spoken one. Empty text does nothing.
    public func submit(_ text: String, pointer: PixelPoint? = nil) {
        isTyping = false
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !closed, !text.isEmpty else { return }
        guard phase == .idle else {
            editor.show(Self.busyMessage)
            return
        }
        guard editor.targetsLoaded else {
            editor.show("Reading text. Try again once it finishes.")
            return
        }
        releasedAt = clock.now
        interpret(text, pointer: pointer ?? editor.hoverPoint)
    }

    // MARK: - Opening

    /// The editor has opened. Once its text is read, a model in effect that the server already holds in memory
    /// reads the screen (`ScreenWarming.warmUpIfLoaded`), so even the first instruction finds it read; a model
    /// that is not loaded waits for D or the typed field, so opening a capture never loads one.
    public func editorOpened() {
        guard !closed else { return }
        guard editor.targetsLoaded else {
            withObservationTracking { _ = editor.targetsLoaded } onChange: { [weak self] in
                Task { @MainActor in self?.editorOpened() }
            }
            return
        }
        guard let warming = model() as? any ScreenWarming else { return }
        warming.warmUpIfLoaded(editor.document.targets)
    }

    // MARK: - Closing and tests

    /// The window is closing: stop listening, drop any answer still coming, change nothing more.
    public func close() {
        closed = true
        transcriber?.cancel()
        listening?.cancel()
        working?.cancel()
        isHeld = false
        isTyping = false
        phase = .idle
    }

    /// Waits for the current steps to finish. For tests.
    public func settle() async {
        while let task = listening ?? working {
            await task.value
            if listening == task { listening = nil }
            if working == task { working = nil }
        }
    }

    // MARK: - Steps

    private func ready(_ transcriber: any SpeechTranscribing) async {
        let readiness = await transcriber.prepare()
        guard !closed, !Task.isCancelled, phase == .preparing else { return }
        if let blocked = Self.status(blockedBy: readiness) { return finish(blocked) }
        if case .needsDownload(let bytes) = readiness {
            guard await download(transcriber, bytes: bytes) else { return }
        }
        guard isHeld else {
            // Released while macOS asked for permission or the model downloaded: ready for the next press.
            phase = .idle
            editor.dictation = nil
            editor.show("Ready. Hold \(editor.keymap.display(for: .dictate)) and speak.")
            return
        }
        do {
            try await transcriber.start(hints: Self.hints(from: editor.document.targets)) { [weak self] text in
                self?.heard(text)
            }
        } catch {
            return finish(.speechUnavailable(reason: "Speech couldn't start: \(error.localizedDescription)."))
        }
        guard !closed, !Task.isCancelled, phase == .preparing else {
            transcriber.cancel()
            return
        }
        phase = .listening
        show(.listening(transcript: ""))
        if !isHeld { await stopListening(transcriber) }
    }

    /// Downloads the speech model. Returns whether it is ready.
    private func download(_ transcriber: any SpeechTranscribing, bytes: Int64?) async -> Bool {
        phase = .downloading
        show(.downloading(progress: 0, bytes: bytes))
        do {
            try await transcriber.download { [weak self] progress in
                guard let self, self.phase == .downloading else { return }
                self.show(.downloading(progress: min(max(progress, 0), 1), bytes: bytes))
            }
            try Task.checkCancellation()
        } catch {
            guard !closed else { return false }
            let cancelled = error is CancellationError || Task.isCancelled
            let again = "Hold \(editor.keymap.display(for: .dictate)) to try again."
            finish(.downloadStopped(reason: cancelled ? "Download cancelled. \(again)"
                                        : "The speech model didn't download: \(error.localizedDescription). \(again)"))
            return false
        }
        guard !closed else { return false }
        phase = .preparing
        return true
    }

    private func heard(_ text: String) {
        guard phase == .listening || phase == .preparing, isHeld else { return }
        show(.listening(transcript: text))
    }

    private func stopListening(_ transcriber: any SpeechTranscribing) async {
        phase = .working
        let text = await transcriber.finish().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !closed else { return }
        guard !text.isEmpty else {
            phase = .idle
            editor.dictation = nil
            return
        }
        interpret(text, pointer: pointer)
    }

    private func interpret(_ text: String, pointer: PixelPoint?) {
        phase = .working
        show(.interpreting(transcript: text, usingModel: false))
        let request = InterpretRequest(instruction: text, targets: editor.document.targets, pointer: pointer)
        working = Task { await self.work(request) }
    }

    private func work(_ request: InterpretRequest) async {
        let text = request.instruction
        let model = model()
        // With no model to try next, a name the screen does not show is reported as not found beside what was
        // done; with one, the grammar declines so the model can read it, as `exhibit say` does.
        var interpretation = GrammarInterpreter.interpret(request, unknownNames: model == nil ? .reportNotFound : .decline)
            .interpretation
        let byModel = interpretation == nil
        if interpretation == nil {
            guard let model else { return finish(.needsModel(transcript: text)) }
            show(.interpreting(transcript: text, usingModel: true))
            do {
                interpretation = try await model.interpret(request).interpretation
            } catch is ModelUnavailable {
                guard !closed, !Task.isCancelled else { return }
                return finish(.needsModel(transcript: text))
            } catch {
                guard !closed, !Task.isCancelled else { return }
                return finish(.modelFailed(transcript: text, reason: Self.reason(for: error)))
            }
        }
        guard !closed, !Task.isCancelled else { return }
        guard let interpretation else { return finish(.nothingUnderstood(transcript: text)) }
        let status = Self.status(for: editor.apply(interpretation, original: original), transcript: text,
                                 byModel: byModel)
        if status.changedMarks, let releasedAt { lastReleaseToMarks = clock.now - releasedAt }
        finish(status)
    }

    /// The person has started an instruction: when a model is in effect and can read a screen ahead
    /// (`ScreenWarming`), it starts reading this one now, while they speak or type, so its answer comes sooner if
    /// the grammar declines. It never waits, and the grammar never waits on it; if the grammar answers, the
    /// warm-up is simply unused. Once per screen (`ModelWarmUps`).
    private func warmUpModel() {
        guard editor.targetsLoaded, let warming = model() as? any ScreenWarming else { return }
        warming.warmUp(editor.document.targets)
    }

    private func show(_ status: DictationStatus) {
        editor.notice = nil
        editor.dictation = status
    }

    private func finish(_ status: DictationStatus) {
        phase = .idle
        isHeld = false
        show(status)
    }
}

extension DictationSession {
    static let busyMessage = "Still working on the last instruction. Try again when it finishes."

    /// Text lines on the screen, for speech to favour. Masked lines (secrets) are left out; at most 100.
    static func hints(from targets: [Target]) -> [String] {
        var seen = Set<String>()
        let lines = targets.compactMap { target -> String? in
            guard target.kind == .text, let text = target.text?.trimmingCharacters(in: .whitespaces), !text.isEmpty,
                  text.count <= 60, !text.contains("\u{2022}"), seen.insert(text).inserted else { return nil }
            return text
        }
        return Array(lines.prefix(100))
    }

    /// What a person sees when speech can't start, or nil when it can (perhaps after a download).
    static func status(blockedBy readiness: SpeechReadiness) -> DictationStatus? {
        switch readiness {
        case .ready, .needsDownload: nil
        case .microphoneDenied: .microphoneDenied
        case .speechDenied: .speechDenied
        case .unavailable(let reason): .speechUnavailable(reason: reason)
        }
    }

    static func status(for result: InstructionResult, transcript: String, byModel: Bool) -> DictationStatus {
        switch result {
        case .applied(let summary, _): .applied(transcript: transcript, summary: summary, byModel: byModel)
        case .partial(let summary, _): .partial(transcript: transcript, summary: summary, byModel: byModel)
        case .nothingFound(let summary): .nothingFound(transcript: transcript, summary: summary)
        case .nothingToDo: .nothingUnderstood(transcript: transcript)
        case .failed: .nothingFound(transcript: transcript, summary: "Couldn't find what it named.")
        }
    }

    /// A model failure in plain words.
    static func reason(for error: Error) -> String {
        guard let error = error as? ModelError else { return "The local model failed: \(error.localizedDescription)." }
        return switch error {
        case .unreachable: "The local model isn't answering. Is it running?"
        case .timedOut(let seconds): "The local model didn't answer within \(Int(seconds)) seconds."
        case .httpStatus(let status, _) where status == 404: "The local model isn't installed on the server."
        case .httpStatus(let status, _): "The local model's server answered HTTP \(status)."
        case .badAnswer: "The local model's answer couldn't be read."
        case .notLoopback: "The model endpoint isn't on this Mac, so nothing was sent."
        case .invalidEndpoint(let detail): "The model endpoint isn't usable: \(detail)."
        }
    }
}
