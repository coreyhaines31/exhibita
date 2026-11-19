import Foundation

/// Whether speech can start, after the first-dictation permission prompts.
public enum SpeechReadiness: Equatable, Sendable {
    case ready
    /// The on-device model for the language has to be downloaded first; size in bytes when the system says.
    case needsDownload(bytes: Int64?)
    case microphoneDenied
    case speechDenied
    /// Speech can't run on this Mac for this language, in words a person reads.
    case unavailable(String)
}

/// Push-to-talk transcription, on the Mac only. The app has two: `SpeechAnalyzer` on macOS 26 and later, and
/// `SFSpeechRecognizer` with on-device recognition required on macOS 14 to 25. Tests use a fake.
///
/// Audio stays in memory: nothing is written to disk, and nothing leaves the Mac.
@MainActor
public protocol SpeechTranscribing: AnyObject {
    /// Asks macOS for microphone (and, where needed, speech) permission the first time it is called, which is the
    /// first time a person holds D, and says whether listening can start. Never called at launch.
    func prepare() async -> SpeechReadiness
    /// Downloads the on-device speech model, reporting progress from 0 to 1. Cancelling the calling task stops it.
    func download(progress: @escaping @MainActor (Double) -> Void) async throws
    /// Starts listening. Partial transcripts arrive as they are heard, each one the whole text so far.
    func start(partial: @escaping @MainActor (String) -> Void) async throws
    /// Stops listening and returns the final transcript, empty when nothing was said.
    func finish() async -> String
    /// Stops listening and drops what was heard.
    func cancel()
}
