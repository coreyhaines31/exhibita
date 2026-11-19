import AppKit
@preconcurrency import AVFoundation
import ExhibitEditor
import Speech

/// The transcriber for this Mac: `SpeechAnalyzer` on macOS 26 and later, `SFSpeechRecognizer` with on-device
/// recognition required on macOS 14 to 25. Creating one asks for nothing; the first hold of D does.
@MainActor
enum SpeechTranscription {
    static func make(locale: Locale = .current) -> any SpeechTranscribing {
        if #available(macOS 26.0, *) { return AnalyzerTranscriber(locale: locale) }
        return RecognizerTranscriber(locale: locale)
    }

    /// "English (United States)", for messages.
    static func name(of locale: Locale) -> String {
        Locale.current.localizedString(forIdentifier: locale.identifier) ?? locale.identifier
    }
}

/// System Settings' privacy panes, for the denied states' links.
enum SystemPrivacy {
    enum Pane: String {
        case microphone = "Privacy_Microphone"
        case speechRecognition = "Privacy_SpeechRecognition"
    }

    @MainActor
    static func open(_ pane: Pane) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane.rawValue)") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}

/// Microphone permission. Asked for only when undetermined, which is the first time someone holds D.
enum Microphone {
    static var isConnected: Bool { AVCaptureDevice.default(for: .audio) != nil }

    static func authorize() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }
}

/// Speech recognition permission, which `SFSpeechRecognizer` needs. Asked for only when undetermined.
enum SpeechPermission {
    static func authorize() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: return true
        case .notDetermined: return await request()
        default: return false
        }
    }

    private static func request() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
    }
}

/// The microphone through `AVAudioEngine`, buffers handed over on the audio thread. Audio stays in memory: no
/// file, no recording kept.
final class MicrophoneTap {
    private var engine: AVAudioEngine?

    /// The input's format, read when listening starts.
    func start(_ consume: @escaping @Sendable (AVAudioPCMBuffer) -> Void) throws {
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 2048, format: format, block: Self.block(consume))
        engine.prepare()
        try engine.start()
        self.engine = engine
    }

    func stop() {
        guard let engine else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        self.engine = nil
    }

    /// Built outside any actor: the tap runs on the audio thread.
    private static func block(_ consume: @escaping @Sendable (AVAudioPCMBuffer) -> Void) -> AVAudioNodeTapBlock {
        { buffer, _ in consume(buffer) }
    }
}

/// Converts microphone buffers to the format speech wants. Used only from the audio thread.
final class BufferConverter: @unchecked Sendable {
    private let target: AVAudioFormat
    private var converter: AVAudioConverter?

    init(to target: AVAudioFormat) {
        self.target = target
    }

    func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        if buffer.format == target { return buffer }
        if converter?.inputFormat != buffer.format { converter = AVAudioConverter(from: buffer.format, to: target) }
        guard let converter else { return nil }
        let ratio = target.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 1
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return nil }
        var handed = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if handed {
                inputStatus.pointee = .noDataNow
                return nil
            }
            handed = true
            inputStatus.pointee = .haveData
            return buffer
        }
        return status == .error || error != nil ? nil : output
    }
}

/// Carries a value the speech APIs share across threads themselves.
final class UncheckedBox<Value>: @unchecked Sendable {
    let value: Value

    init(_ value: Value) {
        self.value = value
    }
}

struct SpeechError: LocalizedError {
    let errorDescription: String?

    init(_ description: String) {
        errorDescription = description
    }
}
