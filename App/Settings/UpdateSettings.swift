import Foundation

/// Settings' view of Sparkle: the app passes the updater's, renders pass a fixture.
struct UpdateSettings {
    var isConfigured = false
    var version = UpdateSettings.bundleVersion
    var checksAutomatically = true
    var setChecksAutomatically: (Bool) -> Void = { _ in }
    var checkNow: () -> Void = {}

    static var bundleVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }
}
