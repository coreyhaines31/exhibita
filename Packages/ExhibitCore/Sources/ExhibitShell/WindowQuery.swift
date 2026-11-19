import CoreGraphics
import Foundation

/// `exhibit capture --window "<app or title>"`: which window a name means.
public enum WindowQuery {
    public enum Match: Equatable, Sendable {
        case found(WindowCandidate)
        case notFound
        /// Several windows fit equally well; the frontmost of each, front to back.
        case ambiguous([WindowCandidate])
    }

    /// Resolves `query` against `windows`, which must be front to back. Only ordinary windows (layer 0, at least
    /// `WindowPicker.minimumSide` on each side) not owned by `excludingPID` count. In order:
    ///
    /// 1. An app whose name or bundle identifier equals the query (ignoring case): its frontmost window.
    /// 2. Windows whose title equals the query: the one, or ambiguous.
    /// 3. Windows whose title contains the query: the one, or ambiguous.
    /// 4. Apps whose name contains the query: the frontmost window of the one app, or ambiguous.
    public static func match(_ query: String, in windows: [WindowCandidate], excludingPID: Int32) -> Match {
        let wanted = fold(query)
        guard !wanted.isEmpty else { return .notFound }
        let ordinary = windows.filter { window in
            window.layer == 0 && window.ownerPID != excludingPID
                && window.frame.width >= WindowPicker.minimumSide && window.frame.height >= WindowPicker.minimumSide
        }
        if let window = ordinary.first(where: { fold($0.ownerName) == wanted || fold($0.bundleIdentifier) == wanted }) {
            return .found(window)
        }
        for test in [{ (title: String) in title == wanted }, { (title: String) in title.contains(wanted) }] {
            let titled = ordinary.filter { window in
                let title = fold(window.title)
                return !title.isEmpty && test(title)
            }
            if titled.count == 1 { return .found(titled[0]) }
            if titled.count > 1 { return .ambiguous(titled) }
        }
        let named = frontmostPerApp(ordinary.filter { fold($0.ownerName).contains(wanted) })
        if named.count == 1 { return .found(named[0]) }
        if named.count > 1 { return .ambiguous(named) }
        return .notFound
    }

    private static func frontmostPerApp(_ windows: [WindowCandidate]) -> [WindowCandidate] {
        var seen: Set<Int32> = []
        return windows.filter { seen.insert($0.ownerPID).inserted }
    }

    private static func fold(_ text: String?) -> String {
        (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
