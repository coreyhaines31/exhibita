import os
import ServiceManagement

/// Launch at login through `SMAppService`, on by default in release builds, as in the sibling apps.
@MainActor
enum LaunchAtLogin {
    private nonisolated static let logger = Logger(subsystem: Brand.bundleIdentifier, category: "LaunchAtLogin")

    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    /// Turns launch at login on once, so the hotkeys work after a restart. Tries again next launch if it fails.
    /// Debug builds skip it so a DerivedData copy never becomes the login item.
    static func applyDefault() {
        #if !DEBUG
        guard !Preferences.appliedLaunchAtLoginDefault else { return }
        guard (try? SMAppService.mainApp.register()) != nil else { return }
        Preferences.appliedLaunchAtLoginDefault = true
        #endif
    }

    /// Returns the state after the change.
    static func set(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            logger.error("Couldn't change launch at login: \(error.localizedDescription)")
        }
        return isEnabled
    }
}
