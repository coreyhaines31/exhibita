import Foundation

/// Screen Recording, as the app can tell without prompting: `CGPreflightScreenCaptureAccess()` says whether it
/// is granted, and the app remembers whether it has asked before.
public enum ScreenRecordingState: Equatable, Sendable {
    case granted
    /// Never asked: the button asks macOS, which adds Exhibit A to the list and shows its own prompt.
    case notAsked
    /// Asked and still off: the person turned it down, or turned it on and macOS wants a relaunch.
    case denied

    public init(preflight: Bool, hasAsked: Bool) {
        if preflight {
            self = .granted
        } else {
            self = hasAsked ? .denied : .notAsked
        }
    }

    public var title: String {
        switch self {
        case .granted: "Screen Recording is on"
        case .notAsked: "Exhibit A needs Screen Recording"
        case .denied: "Screen Recording is off for Exhibit A"
        }
    }

    public var message: String {
        switch self {
        case .granted:
            "Captures stay on this Mac."
        case .notAsked:
            "macOS asks once. It's the only permission Exhibit A needs to capture, and captures stay on this Mac."
        case .denied:
            "Turn on Exhibit A in Privacy & Security, Screen & System Audio Recording. "
                + "If it's already on, quit and reopen Exhibit A."
        }
    }

    public var buttonTitle: String {
        switch self {
        case .granted: "Open Settings"
        case .notAsked: "Allow Screen Recording…"
        case .denied: "Open Privacy & Security…"
        }
    }
}

/// What the panel shows.
public enum PanelContent: Equatable, Sendable {
    /// A hotkey was pressed or the panel opened without the permission: explain it first.
    case permission(ScreenRecordingState)
    case empty
    case history

    public static func resolve(permission: ScreenRecordingState, historyCount: Int) -> PanelContent {
        if permission != .granted { return .permission(permission) }
        return historyCount == 0 ? .empty : .history
    }
}
