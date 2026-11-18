import CoreGraphics
import ExhibitCore

/// Finds the target under the pointer, so a click covers a whole text run or exactly one detected secret.
public struct Snapping: Sendable {
    public let targets: [Target]
    /// How far outside a target's box a click still counts, in image pixels.
    public let slack: Double

    public init(targets: [Target], slack: Double) {
        self.targets = targets
        self.slack = slack
    }

    /// Kinds a click can snap to. Window frames are left out: a click inside a window would always hit it.
    static let snappable: Set<TargetKind> = [.text, .email, .key, .card, .phone, .face]

    /// The target a click at `point` means. A secret or face wins over the line holding it, so a click on an
    /// email inside a sentence covers exactly the email; otherwise the line under the pointer. Among overlapping
    /// candidates of the same rank the smallest wins.
    public func target(at point: PixelPoint) -> Target? {
        let hits = targets.filter { Self.snappable.contains($0.kind) && contains(box(of: $0), point) }
        let specific = hits.filter { $0.kind != .text }
        let pool = specific.isEmpty ? hits : specific
        return pool.min { area(box(of: $0)) < area(box(of: $1)) }
    }

    /// Detected secrets (email, key, card, phone).
    public static func sensitive(_ targets: [Target]) -> [Target] {
        targets.filter { $0.kind.isSensitive }
    }

    /// The box a mark snapped to `target` covers: the union of a line's word boxes when it has them, which hugs
    /// the ink more closely than the line's padded box, otherwise the target's box.
    public func box(of target: Target) -> PixelRect {
        guard target.kind == .text, let spans = target.spans, !spans.isEmpty else { return target.rect.standardized }
        let union = spans.map(\.rect.cgRect).reduce(CGRect.null) { $0.union($1) }
        return PixelRect(x: union.minX, y: union.minY, width: union.width, height: union.height)
    }

    /// Word boxes and target boxes, for placing an arrow tail where it covers no text.
    public var obstacles: [PixelRect] {
        targets.flatMap { target -> [PixelRect] in
            if target.kind == .text, let spans = target.spans, !spans.isEmpty { return spans.map(\.rect.standardized) }
            return [target.rect.standardized]
        }
    }

    private func contains(_ rect: PixelRect, _ point: PixelPoint) -> Bool {
        point.x >= rect.minX - slack && point.x <= rect.maxX + slack
            && point.y >= rect.minY - slack && point.y <= rect.maxY + slack
    }

    private func area(_ rect: PixelRect) -> Double {
        (rect.maxX - rect.minX) * (rect.maxY - rect.minY)
    }
}

extension TargetKind {
    /// Kinds whose text is never stored, and that ⇧B blurs.
    public var isSensitive: Bool {
        [.email, .key, .card, .phone].contains(self)
    }
}

extension PixelRect {
    /// Whether `other` lies entirely inside this rect.
    func covers(_ other: PixelRect) -> Bool {
        other.minX >= minX && other.maxX <= maxX && other.minY >= minY && other.maxY <= maxY
    }

    init(corner first: PixelPoint, _ second: PixelPoint) {
        self.init(x: min(first.x, second.x), y: min(first.y, second.y),
                  width: abs(second.x - first.x), height: abs(second.y - first.y))
    }
}
