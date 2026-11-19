import Foundation

/// Where dictation (or a typed instruction) is, as the status strip shows it. The spec's States table: listening
/// with a live transcript, a short working state, then what was done, never success before marks exist.
public enum DictationStatus: Equatable, Sendable {
    /// D is down and the microphone and speech are being readied (the first time, macOS asks for permission).
    case preparing
    /// The on-device speech model is downloading. Progress from 0 to 1; size in bytes when known. Esc cancels.
    case downloading(progress: Double, bytes: Int64?)
    /// D is held: what has been heard so far.
    case listening(transcript: String)
    /// D was released; the grammar or the local model is reading the instruction.
    case interpreting(transcript: String, usingModel: Bool)
    /// Everything named was found and marked.
    case applied(transcript: String, summary: String, byModel: Bool)
    /// Some of it was marked; the rest is named as not found.
    case partial(transcript: String, summary: String, byModel: Bool)
    /// Nothing named is on the screen. Nothing changed.
    case nothingFound(transcript: String, summary: String)
    /// Nothing in the instruction could be acted on. Nothing changed.
    case nothingUnderstood(transcript: String)
    /// The grammar declined and no local model is set up. Nothing changed.
    case needsModel(transcript: String)
    /// The local model was asked and failed: unreachable, timed out, an unreadable answer. Nothing changed.
    case modelFailed(transcript: String, reason: String)
    case microphoneDenied
    case speechDenied
    /// Speech can't run here, said plainly: no on-device recognition for the language, no microphone.
    case speechUnavailable(reason: String)
    /// The download was cancelled or failed.
    case downloadStopped(reason: String)

    /// The grammar can read these; shown when an instruction needs a model.
    public static let grammarExample = "\u{201C}blur the emails\u{201D}"

    /// Still in progress: listening, readying or working. Finished statuses go away on the next action.
    public var isLive: Bool {
        switch self {
        case .preparing, .downloading, .listening, .interpreting: true
        default: false
        }
    }

    /// What was heard or typed, shown in quotes before the message.
    public var transcript: String? {
        switch self {
        case .listening(let text), .interpreting(let text, _), .applied(let text, _, _), .partial(let text, _, _),
             .nothingFound(let text, _), .nothingUnderstood(let text), .needsModel(let text),
             .modelFailed(let text, _):
            text.isEmpty ? nil : text
        default:
            nil
        }
    }

    /// The message after the transcript.
    public var message: String {
        switch self {
        case .preparing: "Getting the microphone ready"
        case let .downloading(progress, bytes):
            "Downloading the speech model, \(Int((progress * 100).rounded()))%"
                + (bytes.map { " of \(Self.megabytes($0))" } ?? "") + ". Esc cancels."
        case .listening(let text): text.isEmpty ? "Listening. Release D when done." : "Listening"
        case .interpreting(_, let usingModel):
            usingModel ? "Asking the local model. This can take several seconds." : "Working"
        case .applied(_, let summary, let byModel): summary + (byModel ? " Check it; ⌘Z undoes all of it." : "")
        case .partial(_, let summary, let byModel): summary + (byModel ? " Check it; ⌘Z undoes all of it." : "")
        case .nothingFound(_, let summary): summary + " No changes made."
        case .nothingUnderstood: "No changes made."
        case .needsModel:
            "Needs a model: set one up in Settings, or try \(Self.grammarExample)."
        case .modelFailed(_, let reason): "\(reason) No changes made."
        case .microphoneDenied:
            "Exhibit A can't use the microphone. Allow it in System Settings, or press / to type."
        case .speechDenied:
            "Speech recognition is off for Exhibit A. Allow it in System Settings, or press / to type."
        case .speechUnavailable(let reason): "\(reason) Press / to type instead."
        case .downloadStopped(let reason): reason
        }
    }

    /// The whole line: the transcript in quotes, then the message.
    public var text: String {
        guard let transcript else { return message }
        return "\u{201C}\(transcript)\u{201D} \(message)"
    }

    /// The link shown beside the message, if any.
    public var link: DictationLink? {
        switch self {
        case .needsModel, .modelFailed: .modelSettings
        case .microphoneDenied: .microphoneSettings
        case .speechDenied: .speechSettings
        default: nil
        }
    }

    /// Whether this reports a change to the marks.
    public var changedMarks: Bool {
        switch self {
        case .applied, .partial: true
        default: false
        }
    }

    static func megabytes(_ bytes: Int64) -> String {
        let value = Double(bytes) / 1_000_000
        return value >= 10 ? "\(Int(value.rounded())) MB" : String(format: "%.1f MB", value)
    }
}

/// Where a dictation message's link goes.
public enum DictationLink: Equatable, Sendable {
    /// Exhibit A's Settings, Free-form instructions.
    case modelSettings
    /// System Settings, Privacy & Security, Microphone.
    case microphoneSettings
    /// System Settings, Privacy & Security, Speech Recognition.
    case speechSettings

    public var title: String {
        switch self {
        case .modelSettings: "Settings"
        case .microphoneSettings, .speechSettings: "Open System Settings"
        }
    }
}
