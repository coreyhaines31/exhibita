import ExhibitEditor
import ExhibitShell
import ExhibitStore
import Foundation

/// Settings and small state in UserDefaults.
enum Preferences {
    /// Where everything here is kept. Tests swap in their own suite, so they never touch the real app's settings.
    nonisolated(unsafe) static var defaults = UserDefaults.standard

    static let retentionKey = "retention"
    static let customHotkeysKey = "customHotkeys"
    static let customEditorKeysKey = "customEditorKeys"
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

    /// Only the editor keys someone changed, by command id. Defaults are not stored, so a default that moves in a
    /// later version reaches everyone who left that key alone.
    static var editorKeymap: EditorKeymap {
        get {
            guard let data = defaults.data(forKey: customEditorKeysKey),
                  let stored = try? JSONDecoder().decode([String: EditorShortcut].self, from: data) else {
                return .standard
            }
            return EditorKeymap(stored: stored)
        }
        set {
            if newValue.isStandard {
                defaults.removeObject(forKey: customEditorKeysKey)
            } else {
                defaults.set(try? JSONEncoder().encode(newValue.stored), forKey: customEditorKeysKey)
            }
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
