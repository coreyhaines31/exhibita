import AppKit
import CoreGraphics
import ExhibitShell

/// Screen Recording. `isGranted` never prompts; only `request()` does, and only a button calls it.
enum ScreenRecording {
    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!

    static var isGranted: Bool { CGPreflightScreenCaptureAccess() }

    @MainActor static var state: ScreenRecordingState {
        ScreenRecordingState(preflight: isGranted, hasAsked: Preferences.askedForScreenRecording)
    }

    /// Asks macOS once (it adds Exhibit A to the Screen Recording list and shows its own prompt), then opens the
    /// pane. After the first time it only opens the pane.
    @MainActor static func request() {
        if !Preferences.askedForScreenRecording {
            Preferences.askedForScreenRecording = true
            // The system prompt carries its own Open System Settings button.
            _ = CGRequestScreenCaptureAccess()
            return
        }
        NSWorkspace.shared.open(settingsURL)
    }
}

/// macOS's screenshot shortcuts. Read only: see `docs/product/hotkey-takeover.md`.
enum SystemShortcuts {
    /// System Settings, Keyboard. Screenshots are under its Keyboard Shortcuts button; no deeper link is public.
    static let keyboardSettingsURL = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!

    /// Reads the current state. Synchronizes first, since System Settings writes the domain from another process.
    static func read() -> SystemScreenshotShortcuts {
        let domain = "com.apple.symbolichotkeys" as CFString
        CFPreferencesAppSynchronize(domain)
        let value = CFPreferencesCopyAppValue("AppleSymbolicHotKeys" as CFString, domain)
        return SystemScreenshotShortcuts(symbolicHotKeys: value)
    }

    static func openKeyboardSettings() {
        NSWorkspace.shared.open(keyboardSettingsURL)
    }
}
