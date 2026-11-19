import Foundation

/// How long history keeps a capture's original (spec decision 2). Thirty days by default; "discard on export"
/// deletes a capture once it has been exported.
public enum RetentionPolicy: Hashable, Sendable {
    case days(Int)
    /// Deleted when exported. A capture that is never exported still goes after `fallbackDays`, so nothing is
    /// kept forever by accident.
    case discardOnExport

    public static let `default` = RetentionPolicy.days(30)
    public static let fallbackDays = 30
    /// The choices Settings offers, in order.
    public static let choices: [RetentionPolicy] = [.discardOnExport, .days(1), .days(7), .days(30), .days(90)]

    private static let secondsPerDay: TimeInterval = 86_400

    /// How many days a capture that is never exported is kept.
    public var keptDays: Int {
        switch self {
        case .days(let days): max(1, days)
        case .discardOnExport: Self.fallbackDays
        }
    }

    public var discardsOnExport: Bool { self == .discardOnExport }

    /// When a capture taken at `createdAt` is swept.
    public func expiry(of createdAt: Date) -> Date {
        createdAt.addingTimeInterval(TimeInterval(keptDays) * Self.secondsPerDay)
    }

    public func isExpired(createdAt: Date, now: Date) -> Bool {
        expiry(of: createdAt) <= now
    }

    /// Whole days left before the sweep, rounded up, never below zero.
    public func daysLeft(createdAt: Date, now: Date) -> Int {
        let seconds = expiry(of: createdAt).timeIntervalSince(now)
        return max(0, Int((seconds / Self.secondsPerDay).rounded(.up)))
    }

    /// The Settings label.
    public var title: String {
        switch self {
        case .discardOnExport: "Until exported"
        case .days(1): "1 day"
        case .days(let days): "\(days) days"
        }
    }

    /// How the policy is stored in preferences: `"export"` or `"days:30"`.
    public var storageValue: String {
        switch self {
        case .discardOnExport: "export"
        case .days(let days): "days:\(days)"
        }
    }

    public init?(storageValue: String) {
        if storageValue == "export" {
            self = .discardOnExport
            return
        }
        let parts = storageValue.split(separator: ":")
        guard parts.count == 2, parts[0] == "days", let days = Int(parts[1]), days > 0 else { return nil }
        self = .days(days)
    }
}
