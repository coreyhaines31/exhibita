import ExhibitShell
import ExhibitStore
import Foundation

/// Settings and small state in UserDefaults.
enum Preferences {
    /// Where everything here is kept. Tests swap in their own suite, so they never touch the real app's settings.
    nonisolated(unsafe) static var defaults = UserDefaults.standard

    static let retentionKey = "retention"
    static let customHotkeysKey = "customHotkeys"
    static let askedForScreenRecordingKey = "askedForScreenRecording"
    static let appliedLaunchAtLoginDefaultKey = "appliedLaunchAtLoginDefault"

    static var retention: RetentionPolicy {
        get { defaults.string(forKey: retentionKey).flatMap(RetentionPolicy.init(storageValue:)) ?? .default }
        set { defaults.set(newValue.storageValue, forKey: retentionKey) }
    }

    /// Only the hotkeys someone changed. Defaults are not stored, so they follow the takeover state.
    static var customHotkeys: [HotkeyAction: KeyCombo] {
        get {
            guard let data = defaults.data(forKey: customHotkeysKey),
                  let stored = try? JSONDecoder().decode([String: KeyCombo].self, from: data) else { return [:] }
            var result: [HotkeyAction: KeyCombo] = [:]
            for (key, combo) in stored {
                if let action = HotkeyAction(rawValue: key) { result[action] = combo }
            }
            return result
        }
        set {
            let stored = Dictionary(uniqueKeysWithValues: newValue.map { ($0.key.rawValue, $0.value) })
            defaults.set(try? JSONEncoder().encode(stored), forKey: customHotkeysKey)
        }
    }

    /// Set once the app has asked macOS for Screen Recording, so a later "no" reads as denied.
    static var askedForScreenRecording: Bool {
        get { defaults.bool(forKey: askedForScreenRecordingKey) }
        set { defaults.set(newValue, forKey: askedForScreenRecordingKey) }
    }

    static var appliedLaunchAtLoginDefault: Bool {
        get { defaults.bool(forKey: appliedLaunchAtLoginDefaultKey) }
        set { defaults.set(newValue, forKey: appliedLaunchAtLoginDefaultKey) }
    }
}
