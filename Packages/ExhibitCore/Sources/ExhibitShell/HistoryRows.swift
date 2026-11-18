import ExhibitStore
import Foundation

/// One line of the history list, ready to draw.
public struct HistoryRow: Identifiable, Equatable, Sendable {
    public var id: UUID
    /// The app it came from, or "Capture".
    public var title: String
    /// "Today 3:41 PM · 900 × 560".
    public var subtitle: String
    /// "by agent" for agent captures (spec, States).
    public var tag: String?
    /// "Deleted in 3 days", only once the sweep is close.
    public var expiry: String?
    public var isSelected: Bool
}

/// The panel's history list and its empty state.
public enum HistoryPresentation {
    /// Expiry shows once a capture is this many days or fewer from the sweep.
    public static let expiryNoticeDays = 3
    public static let agentTag = "by agent"

    public static func rows(_ items: [HistoryItem], policy: RetentionPolicy, selected: UUID? = nil, now: Date = Date(),
                            calendar: Calendar = .current, locale: Locale = .current) -> [HistoryRow] {
        items.map { item in
            let days = policy.daysLeft(createdAt: item.createdAt, now: now)
            let size = item.pointSize
            return HistoryRow(
                id: item.id,
                title: item.appName ?? item.windowTitle ?? "Capture",
                subtitle: "\(when(item.createdAt, now: now, calendar: calendar, locale: locale)) · "
                    + "\(size.width) × \(size.height)",
                tag: item.byAgent ? agentTag : nil,
                expiry: days <= expiryNoticeDays ? expiryText(days) : nil,
                isSelected: item.id == selected
            )
        }
    }

    /// "Today 3:41 PM", "Yesterday 9:02 AM", "Nov 12, 3:41 PM".
    public static func when(_ date: Date, now: Date, calendar: Calendar, locale: Locale) -> String {
        whenText(date, now: now, calendar: calendar, locale: locale)
            // ICU puts a narrow no-break space before AM and PM; a plain one reads the same and stays searchable.
            .replacingOccurrences(of: "\u{202F}", with: " ")
    }

    private static func whenText(_ date: Date, now: Date, calendar: Calendar, locale: Locale) -> String {
        let time = DateFormatter()
        time.calendar = calendar
        time.timeZone = calendar.timeZone
        time.locale = locale
        time.dateStyle = .none
        time.timeStyle = .short
        if calendar.isDate(date, inSameDayAs: now) { return "Today \(time.string(from: date))" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday \(time.string(from: date))"
        }
        let day = DateFormatter()
        day.calendar = calendar
        day.timeZone = calendar.timeZone
        day.locale = locale
        day.setLocalizedDateFormatFromTemplate("MMMd")
        return "\(day.string(from: date)), \(time.string(from: date))"
    }

    static func expiryText(_ days: Int) -> String {
        switch days {
        case 0: "Deleted today"
        case 1: "Deleted tomorrow"
        default: "Deleted in \(days) days"
        }
    }

    /// The empty state's line under "No captures yet".
    public static func emptyHint(edit: KeyCombo, clipboard: KeyCombo) -> String {
        "Press \(edit.display) to capture and mark up, or \(clipboard.display) to copy a capture."
    }

    /// The fascia's status line: how many captures and how long they are kept.
    public static func summary(count: Int, policy: RetentionPolicy) -> String {
        let captures = count == 1 ? "1 capture" : "\(count) captures"
        switch policy {
        case .discardOnExport: return "\(captures), kept until exported"
        case .days(let days): return "\(captures), kept \(days == 1 ? "1 day" : "\(days) days")"
        }
    }
}
