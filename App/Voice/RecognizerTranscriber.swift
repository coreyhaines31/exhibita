import ExhibitEditor
import Foundation
@preconcurrency import Speech

/// macOS 14 to 25: `SFSpeechRecognizer`, with on-device recognition required. Where the Mac can't recognize the
/// language on device, it says so; it never falls back to Apple's servers, so audio never leaves the Mac.
@MainActor
final class RecognizerTranscriber: SpeechTranscribing {
    private let locale: Locale
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var tap: MicrophoneTap?
    private var heard = ""
    private var isFinal = false
    private var partial: ((String) -> Void)?
    private var ended: CheckedContinuation<Void, Never>?

    init(locale: Locale) {
        self.locale = locale
    }

    func prepare() async -> SpeechReadiness {
        guard Microphone.isConnected else { return .unavailable("No microphone is connected.") }
        guard await Microphone.authorize() else { return .microphoneDenied }
        guard await SpeechPermission.authorize() else { return .speechDenied }
        let name = SpeechTranscription.name(of: locale)
        guard let recognizer = SFSpeechRecognizer(locale: locale) else {
            return .unavailable("Speech recognition doesn't support \(name).")
        }
        guard recognizer.supportsOnDeviceRecognition else {
            return .unavailable("On-device speech isn't available for \(name) on this Mac, and Exhibit A never "
                                + "sends audio off it.")
        }
        guard recognizer.isAvailable else { return .unavailable("Speech recognition isn't available right now.") }
        self.recognizer = recognizer
        return .ready
    }

    /// The on-device model comes with macOS on these systems; there is nothing to download.
    func download(progress: @escaping @MainActor (Double) -> Void) async throws {
        progress(1)
    }

    func start(hints: [String], partial: @escaping @MainActor (String) -> Void) async throws {
        guard let recognizer else { throw SpeechError("Speech isn't ready.") }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.contextualStrings = hints
        heard = ""
        isFinal = false
        self.partial = partial
        let box = UncheckedBox(request)
        let tap = MicrophoneTap()
        try tap.start { buffer in box.value.append(buffer) }
        self.tap = tap
        self.request = request
        task = recognizer.recognitionTask(with: request, resultHandler: Self.handler { [weak self] text, done in
            Task { @MainActor in self?.update(text, done: done) }
        })
    }

    func finish() async -> String {
        tap?.stop()
        tap = nil
        request?.endAudio()
        if !isFinal {
            await withCheckedContinuation { continuation in
                ended = continuation
                // The last result normally comes within a few hundred milliseconds; never wait forever.
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(2))
                    self?.end()
                }
            }
        }
        task = nil
        request = nil
        partial = nil
        return heard
    }

    func cancel() {
        tap?.stop()
        tap = nil
        task?.cancel()
        task = nil
        request = nil
        partial = nil
        end()
    }

    private func update(_ text: String?, done: Bool) {
        if let text, !isFinal {
            heard = text
            partial?(text)
        }
        if done {
            isFinal = true
            end()
        }
    }

    private func end() {
        ended?.resume()
        ended = nil
    }

    /// Built outside any actor: results arrive on the recognizer's queue.
    private nonisolated static func handler(_ report: @escaping @Sendable (String?, Bool) -> Void)
        -> @Sendable (SFSpeechRecognitionResult?, Error?) -> Void {
        { result, error in
            report(result?.bestTranscription.formattedString, (result?.isFinal ?? false) || error != nil)
        }
    }
}
