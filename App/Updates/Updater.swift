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

    private let controller = SPUStandardUpdaterController(
        startingUpdater: Updater.isConfigured,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

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
