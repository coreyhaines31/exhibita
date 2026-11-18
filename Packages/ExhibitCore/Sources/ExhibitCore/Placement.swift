import CoreGraphics
import Foundation

/// Picks where arrows start and where text labels and step discs go, so they point at or sit beside a target
/// without covering it, stay inside the image, and avoid other text where they can.
///
/// Every choice is a short list of candidates scored the same way: candidates that leave the image are dropped,
/// then the fewest collisions with obstacles (words and marks) wins, then plain background over busy pixels, then
/// the earlier (preferred) candidate. Deterministic.
public struct Placement: Sendable {
    public let imageSize: PixelSize
    public let layout: MarkLayout
    /// Busy pixels no target covers, such as a blur from an earlier call on a chained file.
    public var clutter: Clutter?

    public init(imageSize: PixelSize, layout: MarkLayout, clutter: Clutter? = nil) {
        self.imageSize = imageSize
        self.layout = layout
        self.clutter = clutter
    }

    public var unit: Double { layout.unit }
    /// Space kept between a mark and the thing it points at or sits beside.
    public var gap: Double { 6 * unit }
    /// Space kept between a mark and the image edge.
    public var margin: Double { 4 * unit }

    // MARK: Arrows

    public struct Arrow: Equatable, Sendable {
        public var from: PixelPoint
        public var to: PixelPoint
        public var caption: PixelRect?
    }

    /// Tail directions, as unit vectors from the target out to the tail, most preferred first: from below left,
    /// the way most callouts are drawn, then the other diagonals, then straight on, then the in-between angles.
    static let tailDirections: [CGVector] = {
        let degrees: [Double] = [135, 225, 45, 315, 180, 90, 270, 0, 157.5, 112.5, 202.5, 247.5, 67.5, 22.5, 292.5, 337.5]
        // Angles in screen space: 0 is right, 90 is down.
        return degrees.map { CGVector(dx: cos($0 * .pi / 180), dy: sin($0 * .pi / 180)) }
    }()

    /// Shaft lengths to try, in units, most preferred first.
    static let arrowLengths: [Double] = [90, 65, 120, 45]

    /// An arrow whose head stops just outside `target`. With `from`, the tail is fixed and the head lands on the
    /// target's edge facing it; without, the tail is chosen from `tailDirections` and `arrowLengths`.
    public func arrow(to target: PixelRect, from: PixelPoint?, label: String?, obstacles: [PixelRect]) -> Arrow {
        let padded = target.cgRect.insetBy(dx: -gap, dy: -gap)
        let center = CGPoint(x: padded.midX, y: padded.midY)
        if let from {
            let tail = from.cgPoint
            let head = padded.contains(tail) ? center
                : Self.exit(from: center, along: CGVector(dx: tail.x - center.x, dy: tail.y - center.y), in: padded)
            return makeArrow(tail: tail, head: head, label: label)
        }
        let blockers = obstacles.filter { !$0.cgRect.intersects(padded) }
        var best: (score: Int, arrow: Arrow)?
        var rank = 0
        for direction in Self.tailDirections {
            let head = Self.exit(from: center, along: direction, in: padded)
            for length in Self.arrowLengths {
                defer { rank += 1 }
                let tail = CGPoint(x: head.x + direction.dx * length * unit, y: head.y + direction.dy * length * unit)
                let arrow = makeArrow(tail: tail, head: head, label: label)
                guard inside(CGRect(origin: tail, size: .zero)), arrow.caption.map({ inside($0.cgRect) }) ?? true else {
                    continue
                }
                let hits = shaftHits(from: tail, to: head, blockers) + (arrow.caption.map { hits($0.cgRect, blockers) } ?? 0)
                let busy = isBusy(tail: tail, head: head, caption: arrow.caption)
                let score = hits * 1000 + (busy ? 300 : 0) + rank
                if best == nil || score < best!.score { best = (score, arrow) }
            }
        }
        if let best { return best.arrow }
        // Nothing fits (a tiny image): point from the image centre.
        let middle = CGPoint(x: Double(imageSize.width) / 2, y: Double(imageSize.height) / 2)
        let head = padded.contains(middle) ? center
            : Self.exit(from: center, along: CGVector(dx: middle.x - center.x, dy: middle.y - center.y), in: padded)
        return makeArrow(tail: middle, head: head, label: label)
    }

    private func makeArrow(tail: CGPoint, head: CGPoint, label: String?) -> Arrow {
        let from = PixelPoint(x: tail.x, y: tail.y)
        let to = PixelPoint(x: head.x, y: head.y)
        return Arrow(from: from, to: to, caption: label.flatMap { layout.captionRect(from: from, to: to, label: $0) })
    }

    /// Whether the shaft (short of the head, which sits by the busy target) or the caption crosses busy pixels.
    private func isBusy(tail: CGPoint, head: CGPoint, caption: PixelRect?) -> Bool {
        guard let clutter else { return false }
        let nearHead = CGPoint(x: tail.x + (head.x - tail.x) * 0.8, y: tail.y + (head.y - tail.y) * 0.8)
        if clutter.isBusy(from: tail, to: nearHead) { return true }
        guard let caption else { return false }
        return clutter.isBusy(caption.cgRect.insetBy(dx: -gap, dy: -gap))
    }

    /// Where a ray from `origin` (inside `rect`) along `direction` leaves `rect`.
    static func exit(from origin: CGPoint, along direction: CGVector, in rect: CGRect) -> CGPoint {
        let length = (direction.dx * direction.dx + direction.dy * direction.dy).squareRoot()
        guard length > 0 else { return origin }
        let dx = direction.dx / length
        let dy = direction.dy / length
        var reach = Double.greatestFiniteMagnitude
        if dx > 1e-9 { reach = min(reach, (rect.maxX - origin.x) / dx) }
        if dx < -1e-9 { reach = min(reach, (rect.minX - origin.x) / dx) }
        if dy > 1e-9 { reach = min(reach, (rect.maxY - origin.y) / dy) }
        if dy < -1e-9 { reach = min(reach, (rect.minY - origin.y) / dy) }
        return CGPoint(x: origin.x + dx * reach, y: origin.y + dy * reach)
    }

    /// Obstacles the shaft passes through, sampled every couple of units.
    private func shaftHits(from tail: CGPoint, to head: CGPoint, _ obstacles: [PixelRect]) -> Int {
        let length = hypot(head.x - tail.x, head.y - tail.y)
        let steps = max(2, Int(length / (2 * unit)))
        let pad = 2 * unit
        return obstacles.filter { obstacle in
            let box = obstacle.cgRect.insetBy(dx: -pad, dy: -pad)
            return (0...steps).contains { step in
                let along = Double(step) / Double(steps)
                let sample = CGPoint(x: tail.x + (head.x - tail.x) * along, y: tail.y + (head.y - tail.y) * along)
                return box.contains(sample)
            }
        }.count
    }

    // MARK: Labels and steps

    /// The top-left corner for a label of `size` beside `target`: right, below, above, then left.
    public func label(size: CGSize, beside target: PixelRect, obstacles: [PixelRect]) -> PixelRect {
        let box = target.cgRect
        let space = 2 * gap
        let middleY = box.midY - size.height / 2
        let spots = [
            CGPoint(x: box.maxX + space, y: middleY),
            CGPoint(x: box.minX, y: box.maxY + space),
            CGPoint(x: box.minX, y: box.minY - space - size.height),
            CGPoint(x: box.minX - space - size.width, y: middleY),
            CGPoint(x: box.maxX - size.width, y: box.maxY + space),
            CGPoint(x: box.maxX - size.width, y: box.minY - space - size.height)
        ].map { CGRect(origin: $0, size: size) }
        let chosen = choose(spots, avoiding: obstacles, keepingClearOf: box)
        return PixelRect(x: chosen.minX, y: chosen.minY, width: chosen.width, height: chosen.height)
    }

    /// The centre of a step disc beside `target`: left, then above left, right, above and below.
    public func step(beside target: PixelRect, obstacles: [PixelRect]) -> PixelPoint {
        let box = target.cgRect
        let diameter = layout.stepDiameter
        let radius = diameter / 2
        let centers = [
            CGPoint(x: box.minX - gap - radius, y: box.midY),
            CGPoint(x: box.minX - radius / 2, y: box.minY - gap - radius / 2),
            CGPoint(x: box.maxX + gap + radius, y: box.midY),
            CGPoint(x: box.midX, y: box.minY - gap - radius),
            CGPoint(x: box.midX, y: box.maxY + gap + radius)
        ]
        let spots = centers.map { CGRect(x: $0.x - radius, y: $0.y - radius, width: diameter, height: diameter) }
        let chosen = choose(spots, avoiding: obstacles, keepingClearOf: box)
        return PixelPoint(x: chosen.midX, y: chosen.midY)
    }

    /// The spot with the fewest collisions among those inside the image, earlier spots winning ties. When none
    /// fits, the first spot moved inside the image.
    private func choose(_ spots: [CGRect], avoiding obstacles: [PixelRect], keepingClearOf target: CGRect) -> CGRect {
        let padded = target.insetBy(dx: -gap, dy: -gap)
        let blockers = obstacles.filter { !$0.cgRect.intersects(padded) }
        let fitting = spots.filter { inside($0) && !$0.intersects(target) }
        if let best = fitting.enumerated().min(by: { lhs, rhs in
            (hits(lhs.element, blockers), busy(lhs.element), lhs.offset)
                < (hits(rhs.element, blockers), busy(rhs.element), rhs.offset)
        }) {
            return best.element
        }
        return clamped(spots[0])
    }

    private func busy(_ rect: CGRect) -> Int {
        clutter?.isBusy(rect.insetBy(dx: -gap, dy: -gap)) == true ? 1 : 0
    }

    private func hits(_ rect: CGRect, _ obstacles: [PixelRect]) -> Int {
        let box = rect.insetBy(dx: -unit, dy: -unit)
        return obstacles.filter { $0.cgRect.intersects(box) }.count
    }

    private func inside(_ rect: CGRect) -> Bool {
        rect.minX >= margin && rect.minY >= margin
            && rect.maxX <= Double(imageSize.width) - margin && rect.maxY <= Double(imageSize.height) - margin
    }

    private func clamped(_ rect: CGRect) -> CGRect {
        let x = min(max(rect.minX, 0), max(0, Double(imageSize.width) - rect.width))
        let y = min(max(rect.minY, 0), max(0, Double(imageSize.height) - rect.height))
        return CGRect(x: x, y: y, width: rect.width, height: rect.height)
    }
}
