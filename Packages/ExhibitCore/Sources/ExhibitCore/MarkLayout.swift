import CoreGraphics
import CoreText
import Foundation

/// The sizes the renderer will give marks, so callers (the CLI's placement) can lay marks out before rendering.
public struct MarkLayout: Sendable {
    let metrics: MarkMetrics

    /// Layout for an image of `imageSize` drawn at `scale`, or at the scale `Renderer` infers when `scale` is nil.
    public init(scale: Double?, imageSize: PixelSize) {
        metrics = MarkMetrics(unit: scale ?? MarkMetrics.inferredUnit(width: imageSize.width, height: imageSize.height))
    }

    /// One unit in pixels: stroke widths, gaps and label sizes are multiples of it.
    public var unit: Double { metrics.unit }

    /// The diameter of a step disc.
    public var stepDiameter: Double { metrics.stepDiameter }

    /// The size of a text mark's label or an arrow's caption, backing included.
    public func labelSize(_ text: String) -> CGSize {
        Self.labelSize(text, metrics: metrics)
    }

    /// The box an arrow's caption is drawn in, beyond the tail on the far side from the head.
    public func captionRect(from tail: PixelPoint, to tip: PixelPoint, label: String) -> PixelRect? {
        guard !label.isEmpty else { return nil }
        let box = Self.captionRect(tail: tail.cgPoint, tip: tip.cgPoint, size: Self.labelSize(label, metrics: metrics),
                                   gap: metrics.labelGap)
        return PixelRect(x: box.minX, y: box.minY, width: box.width, height: box.height)
    }

    static func captionRect(tail: CGPoint, tip: CGPoint, size: CGSize, gap: Double) -> CGRect {
        let dx = tip.x - tail.x
        let dy = tip.y - tail.y
        let length = max((dx * dx + dy * dy).squareRoot(), .ulpOfOne)
        let dirX = dx / length
        let dirY = dy / length
        let reach = abs(dirX) * size.width / 2 + abs(dirY) * size.height / 2 + gap
        let center = CGPoint(x: tail.x - dirX * reach, y: tail.y - dirY * reach)
        return CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width,
                      height: size.height)
    }

    static func labelSize(_ text: String, metrics: MarkMetrics) -> CGSize {
        let bounds = LineBounds(makeLine(text, size: metrics.labelFontSize, color: RGB(1, 1, 1)))
        let pad = metrics.labelPadding
        return CGSize(width: bounds.width + pad.width * 2, height: bounds.ascent + bounds.descent + pad.height * 2)
    }

    static func labelFont(size: Double) -> CTFont {
        CTFontCreateUIFontForLanguage(.emphasizedSystem, size, nil)
            ?? CTFontCreateWithName("Helvetica-Bold" as CFString, size, nil)
    }

    static func makeLine(_ text: String, size: Double, color: RGB) -> CTLine {
        // One line only: newlines become spaces.
        let singleLine = text.replacingOccurrences(of: "\n", with: " ")
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): labelFont(size: size),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): srgb(color)
        ]
        return CTLineCreateWithAttributedString(NSAttributedString(string: singleLine, attributes: attributes))
    }
}
