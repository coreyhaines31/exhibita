import CoreGraphics
import ExhibitCore

/// A grab point on a selected mark: a corner of a rect mark, or an end of an arrow.
public enum MarkHandle: CaseIterable, Sendable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
    case tail
    case head
}

/// Which mark is under the pointer, what a person sees of each mark, and where its handles are.
public struct MarkHitTesting: Sendable {
    public let layout: MarkLayout
    /// How far from a mark a click still hits it, in image pixels.
    public let tolerance: Double

    public init(layout: MarkLayout, tolerance: Double) {
        self.layout = layout
        self.tolerance = tolerance
    }

    /// The topmost mark at `point`. Blurs sit under everything else, so they are tested last.
    public func mark(at point: PixelPoint, in marks: [Mark]) -> Mark? {
        let order = marks.filter { $0.kind != .blur }.reversed() + marks.filter { $0.kind == .blur }.reversed()
        return order.first { hits($0, point) }
    }

    /// The area a person sees: a label's backing, a step's disc, a circle's padded ellipse box.
    public func visibleBox(of mark: Mark) -> PixelRect {
        let bounds = mark.bounds
        switch mark.kind {
        case .text:
            let size = layout.labelSize(mark.style.label ?? "")
            return PixelRect(x: bounds.minX, y: bounds.minY, width: size.width, height: size.height)
        case .step:
            let diameter = layout.stepDiameter
            return PixelRect(x: bounds.midX - diameter / 2, y: bounds.midY - diameter / 2, width: diameter,
                             height: diameter)
        case .circle:
            let padX = bounds.width / 2 * (2.0.squareRoot() - 1) + 6 * layout.unit
            let padY = bounds.height / 2 * (2.0.squareRoot() - 1) + 6 * layout.unit
            return PixelRect(x: bounds.minX - padX, y: bounds.minY - padY, width: bounds.width + 2 * padX,
                             height: bounds.height + 2 * padY)
        case .arrow, .blur, .highlight, .box:
            return bounds
        }
    }

    /// Handles a selected mark offers. Text labels and steps only move.
    public func handles(of mark: Mark) -> [(MarkHandle, PixelPoint)] {
        switch (mark.kind, mark.geometry) {
        case let (.arrow, .line(from, to)):
            return [(.tail, from), (.head, to)]
        case (.text, _), (.step, _):
            return []
        default:
            let box = mark.bounds
            return [(.topLeft, PixelPoint(x: box.minX, y: box.minY)), (.topRight, PixelPoint(x: box.maxX, y: box.minY)),
                    (.bottomLeft, PixelPoint(x: box.minX, y: box.maxY)),
                    (.bottomRight, PixelPoint(x: box.maxX, y: box.maxY))]
        }
    }

    /// The handle of `mark` under `point`, if any.
    public func handle(at point: PixelPoint, of mark: Mark) -> MarkHandle? {
        handles(of: mark).first { distance($0.1, point) <= tolerance * 1.5 }?.0
    }

    private func hits(_ mark: Mark, _ point: PixelPoint) -> Bool {
        if case let .line(from, to) = mark.geometry {
            if let label = mark.style.label, let caption = layout.captionRect(from: from, to: to, label: label),
               inside(caption, point, pad: 0) {
                return true
            }
            return segmentDistance(point, from, to) <= tolerance + 2 * layout.unit
        }
        return inside(visibleBox(of: mark), point, pad: tolerance)
    }

    private func inside(_ rect: PixelRect, _ point: PixelPoint, pad: Double) -> Bool {
        point.x >= rect.minX - pad && point.x <= rect.maxX + pad && point.y >= rect.minY - pad
            && point.y <= rect.maxY + pad
    }

    private func distance(_ lhs: PixelPoint, _ rhs: PixelPoint) -> Double {
        ((lhs.x - rhs.x) * (lhs.x - rhs.x) + (lhs.y - rhs.y) * (lhs.y - rhs.y)).squareRoot()
    }

    private func segmentDistance(_ point: PixelPoint, _ start: PixelPoint, _ end: PixelPoint) -> Double {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return distance(point, start) }
        let along = max(0, min(1, ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared))
        return distance(point, PixelPoint(x: start.x + along * dx, y: start.y + along * dy))
    }
}

extension Mark {
    /// The mark moved by `dx`, `dy`.
    func offset(dx: Double, dy: Double) -> Mark {
        var moved = self
        switch geometry {
        case .rect(let rect):
            moved.geometry = .rect(PixelRect(x: rect.x + dx, y: rect.y + dy, width: rect.width, height: rect.height))
        case let .line(from, to):
            moved.geometry = .line(from: PixelPoint(x: from.x + dx, y: from.y + dy),
                                   to: PixelPoint(x: to.x + dx, y: to.y + dy))
        }
        return moved
    }

    /// The mark with `handle` dragged to `point`. A rect keeps the opposite corner fixed.
    func resized(_ handle: MarkHandle, to point: PixelPoint) -> Mark {
        var resized = self
        switch geometry {
        case let .line(from, to):
            if handle == .tail { resized.geometry = .line(from: point, to: to) }
            if handle == .head { resized.geometry = .line(from: from, to: point) }
        case .rect:
            let box = bounds
            let opposite: PixelPoint
            switch handle {
            case .topLeft: opposite = PixelPoint(x: box.maxX, y: box.maxY)
            case .topRight: opposite = PixelPoint(x: box.minX, y: box.maxY)
            case .bottomLeft: opposite = PixelPoint(x: box.maxX, y: box.minY)
            case .bottomRight: opposite = PixelPoint(x: box.minX, y: box.minY)
            case .tail, .head: return self
            }
            resized.geometry = .rect(PixelRect(corner: opposite, point))
        }
        // A resized mark no longer sits exactly on its target.
        resized.targetID = nil
        return resized
    }
}
