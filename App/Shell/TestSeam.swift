import ExhibitShell
import ExhibitStore
import Foundation

/// Debug builds only: runs the real app on throwaway state for the app-hosted end-to-end tests
/// (`ExhibitAE2ETests`, `Scripts/run-e2e.sh`). Release builds compile it to "off" and never read the variables.
///
/// It turns on when `EXHIBIT_SUPPORT_DIR` is set, or when XCTest hosts the app. Then history, the policy file,
/// the bridge socket and ⇧⌘C files live under a temporary support directory, preferences go to a throwaway
/// defaults suite (`EXHIBIT_DEFAULTS_SUITE`), the global hotkeys are not registered, the status item does not save
/// its position, Sparkle never starts, and Screen Recording reads as off (`ScreenRecording.forcedOff`), so nothing
/// can capture the screen. Hosted by XCTest without the variables, it makes its own temporary ones,
/// so a test run never touches the real captures or settings.
///
/// `EXHIBIT_E2E_ALLOW_CAPTURE=1` (set only by `Scripts/run-e2e-capture.sh`) leaves Screen Recording to what
/// `CGPreflightScreenCaptureAccess` says, so `CaptureTests` can take real captures into the temporary support
/// directory. It never asks for the permission; without it those tests skip.
enum TestSeam {
    static let supportVariable = ExhibitPaths.supportOverrideVariable
    static let defaultsSuiteVariable = "EXHIBIT_DEFAULTS_SUITE"
    static let allowCaptureVariable = "EXHIBIT_E2E_ALLOW_CAPTURE"

    struct Configuration {
        let supportDirectory: URL
        let defaultsSuite: String
    }

    /// Nil in release builds and in a normal launch.
    static let configuration: Configuration? = {
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        let hostedByXCTest = environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil
        let support = environment[supportVariable].flatMap { $0.isEmpty ? nil : $0 }
        guard support != nil || hostedByXCTest else { return nil }
        let token = UUID().uuidString.prefix(8).lowercased()
        // Short, because the bridge socket's path must fit a Unix socket address (104 bytes).
        let directory = support.map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("xa-e2e-\(token)", isDirectory: true)
        let suite = environment[defaultsSuiteVariable].flatMap { $0.isEmpty ? nil : $0 }
            ?? "com.exhibitaformac.e2e.\(token)"
        return Configuration(supportDirectory: directory.standardizedFileURL, defaultsSuite: suite)
        #else
        return nil
        #endif
    }()

    static var isActive: Bool { configuration != nil }

    /// Real captures allowed under the seam: debug builds, seam on, `EXHIBIT_E2E_ALLOW_CAPTURE=1`.
    static let allowsCapture: Bool = {
        #if DEBUG
        return isActive && ProcessInfo.processInfo.environment[allowCaptureVariable] == "1"
        #else
        return false
        #endif
    }()

    /// Points `Preferences` at the throwaway suite. Call first thing at launch, before anything reads a setting.
    static func applyDefaults() {
        guard let configuration, let suite = UserDefaults(suiteName: configuration.defaultsSuite) else { return }
        Preferences.defaults = suite
    }

    /// The captures folder: the temporary one while active, otherwise the real one.
    static func capturesDirectory() throws -> URL {
        if let configuration { return ExhibitPaths.capturesDirectory(in: configuration.supportDirectory) }
        return try CaptureStore.defaultDirectory()
    }

    /// Where ⇧⌘C writes its files while active, so test files never land beside the real app's.
    static var exportsFolder: URL? {
        configuration?.supportDirectory.appendingPathComponent("Exports", isDirectory: true)
    }
}
