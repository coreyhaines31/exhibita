import ExhibitShell
import Foundation
import Sparkle

/// Sparkle updates, fed from the appcast attached to each GitHub release. With the public key still a placeholder
/// (every build before the first release) the updater never starts, so nothing goes online.
@MainActor
final class Updater {
    static var isConfigured: Bool {
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
        return !key.isEmpty && !key.hasPrefix("REPLACE_WITH") && !TestSeam.isActive
    }

    /// Started from `start()` once the app has launched, so the launch check can follow it at once, as Sparkle asks.
    private let controller = SPUStandardUpdaterController(
        startingUpdater: false,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )
    private var started = false

    /// Starts Sparkle, then looks for an update in the background when one is due (`UpdateCheckSchedule`): with
    /// automatic checks on and the last check over an hour old. Nothing shows unless an update exists. Once per
    /// launch; never under the test seam or with a placeholder key.
    func start(now: Date = Date()) {
        guard Self.isConfigured, !started else { return }
        started = true
        controller.startUpdater()
        let updater = controller.updater
        // Sparkle: call checkForUpdatesInBackground only immediately after starting, and only with automatic checks on.
        if UpdateCheckSchedule.isDueAtLaunch(lastCheck: updater.lastUpdateCheckDate, now: now,
                                             checksAutomatically: updater.automaticallyChecksForUpdates) {
            updater.checkForUpdatesInBackground()
        }
    }

    var checksAutomatically: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    func checkForUpdates() {
        guard Self.isConfigured else { return }
        controller.checkForUpdates(nil)
    }

    /// What Settings shows and does, without Sparkle, so renders and tests build without it.
    var settings: UpdateSettings {
        UpdateSettings(isConfigured: Self.isConfigured, version: UpdateSettings.bundleVersion,
                       checksAutomatically: checksAutomatically,
                       setChecksAutomatically: { [weak self] in self?.checksAutomatically = $0 },
                       checkNow: { [weak self] in self?.checkForUpdates() })
    }
}
