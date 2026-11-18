import ExhibitCore
import Foundation

/// The target list as a model reads it: short references (`t1`, `t2`, ...) in reading order, one line each.
///
/// Models answer with references, never coordinates, and only references from this listing are accepted, so a model
/// can only ever choose among the targets that were found. Sensitive targets appear as "(hidden email)" and so on;
/// their characters are already masked in the lines they came from.
public struct TargetListing: Sendable {
    public struct Entry: Sendable, Equatable {
        public var ref: String
        public var target: Target
    }

    public let entries: [Entry]
    /// The target under the pointer, when the request has a pointer and one is close enough.
    public let pointed: Entry?

    public init(_ request: InterpretRequest) {
        let listed = Self.listable(request.targets)
        let entries = listed.enumerated().map { Entry(ref: "t\($0.offset + 1)", target: $0.element) }
        let underPointer = request.pointer.flatMap { Self.target(at: $0, in: listed) }
        self.entries = entries
        pointed = underPointer.flatMap { target in entries.first { $0.target.id == target.id } }
    }

    public var refs: [String] { entries.map(\.ref) }

    public func target(ref: String) -> Target? {
        let wanted = ref.trimmingCharacters(in: .whitespaces).lowercased()
        return entries.first { $0.ref == wanted }?.target
    }

    /// One line per target: `t12 text "Update plan" at 294,224 size 86x14`.
    public var text: String {
        entries.map { entry in
            let target = entry.target
            let rect = target.rect.standardized
            let what: String = switch target.kind {
            case .text: "text \"\(target.text ?? "")\""
            case .face: "face"
            case .email, .key, .card, .phone: "\(target.kind.rawValue) (hidden \(Self.noun(for: target.kind)))"
            default: target.kind.rawValue
            }
            return "\(entry.ref) \(what) at \(Int(rect.minX)),\(Int(rect.minY)) size \(Int(rect.width))x\(Int(rect.height))"
        }.joined(separator: "\n")
    }

    /// The pointer as a model reads it, or nil when there is no pointer.
    public func pointerText(_ pointer: PixelPoint?) -> String? {
        guard let pointer else { return nil }
        let at = "The pointer is at \(Int(pointer.x)),\(Int(pointer.y))"
        guard let pointed else { return at + ", not over any listed target." }
        return at + ", over \(pointed.ref)."
    }

    /// Targets worth listing. A text line whose every character is masked, sitting exactly where a sensitive target
    /// is, says nothing the sensitive target does not, and listing both invites a model to pick the wrong one.
    static func listable(_ targets: [Target]) -> [Target] {
        let sensitive = targets.filter { [.email, .key, .card, .phone].contains($0.kind) }
        return targets.filter { target in
            guard target.kind == .text, let text = target.text, !text.isEmpty,
                  text.allSatisfy({ $0 == "\u{2022}" || $0 == " " }) else { return true }
            return !sensitive.contains { Self.nearlyEqual($0.rect, target.rect) }
        }
    }

    /// The target a pointer is over: the smallest one containing it (a key inside its line wins over the line), or
    /// failing that the nearest within a few pixels.
    public static func target(at point: PixelPoint, in targets: [Target], slack: Double = 6) -> Target? {
        let containing = targets.filter { grown($0.rect, by: slack).contains(point) }
        if let smallest = containing.min(by: { area($0.rect) < area($1.rect) }) { return smallest }
        return nil
    }

    private static func noun(for kind: TargetKind) -> String {
        switch kind {
        case .email: "email address"
        case .key: "key or password"
        case .card: "card number"
        case .phone: "phone number"
        default: kind.rawValue
        }
    }

    private static func nearlyEqual(_ lhs: PixelRect, _ rhs: PixelRect) -> Bool {
        let lhs = lhs.standardized, rhs = rhs.standardized
        return abs(lhs.minX - rhs.minX) <= 2 && abs(lhs.minY - rhs.minY) <= 2
            && abs(lhs.maxX - rhs.maxX) <= 2 && abs(lhs.maxY - rhs.maxY) <= 2
    }

    private static func grown(_ rect: PixelRect, by slack: Double) -> PixelRect {
        let rect = rect.standardized
        return PixelRect(x: rect.minX - slack, y: rect.minY - slack, width: rect.width + 2 * slack,
                         height: rect.height + 2 * slack)
    }

    private static func area(_ rect: PixelRect) -> Double { abs(rect.width * rect.height) }
}

extension PixelRect {
    func contains(_ point: PixelPoint) -> Bool {
        point.x >= minX && point.x <= maxX && point.y >= minY && point.y <= maxY
    }
}
