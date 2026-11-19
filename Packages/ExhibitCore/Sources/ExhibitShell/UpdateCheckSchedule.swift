import Foundation

/// Whether to look for an update at launch (issue 94). Sparkle's own schedule is about daily and does not run at
/// launch, so a Mac that only runs Exhibit A now and then could go weeks without hearing of a release.
public enum UpdateCheckSchedule {
    /// How old the last check must be before launch checks again.
    public static let minimumAge: TimeInterval = 60 * 60

    /// Due when automatic checks are on and the last check is more than `minimumAge` old, never happened, or is in
    /// the future (the clock was set back).
    public static func isDueAtLaunch(lastCheck: Date?, now: Date, checksAutomatically: Bool) -> Bool {
        guard checksAutomatically else { return false }
        guard let lastCheck else { return true }
        let age = now.timeIntervalSince(lastCheck)
        return age > minimumAge || age < 0
    }
}
