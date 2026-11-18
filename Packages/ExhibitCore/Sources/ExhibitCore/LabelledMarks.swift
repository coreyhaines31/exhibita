import CoreGraphics
import CoreText
import Foundation

extension MarkPainter {
    func drawArrow(from tail: CGPoint, to tip: CGPoint, color: MarkColor, label: String?) {
        let dx = tip.x - tail.x
        let dy = tip.y - tail.y
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > 0.5 else { return }
        let dirX = dx / length
        let dirY = dy / length

        // Short arrows get a proportionally smaller head so the shaft still shows.
        let headScale = min(1, length / (metrics.arrowHeadLength * 1.6))
        let headLength = metrics.arrowHeadLength * headScale
        let halfWidth = metrics.arrowHeadHalfWidth * headScale
        let base = CGPoint(x: tip.x - dirX * headLength, y: tip.y - dirY * headLength)
        // The shaft stops inside the head so its round cap never pokes past the head's sides.
        let shaftEnd = CGPoint(x: tip.x - dirX * headLength * 0.6, y: tip.y - dirY * headLength * 0.6)

        setShadow()
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        context.setStrokeColor(srgb(color.rgb))
        context.setFillColor(srgb(color.rgb))
        context.setLineWidth(metrics.arrowStroke * max(0.6, headScale))
        context.setLineCap(.round)
        context.move(to: tail)
        context.addLine(to: shaftEnd)
        context.strokePath()

        // A slightly swept-back head reads as a pointer rather than a plain triangle.
        let notch = CGPoint(x: tip.x - dirX * headLength * 0.78, y: tip.y - dirY * headLength * 0.78)
        context.move(to: tip)
        context.addLine(to: CGPoint(x: base.x - dirY * halfWidth, y: base.y + dirX * halfWidth))
        context.addLine(to: notch)
        context.addLine(to: CGPoint(x: base.x + dirY * halfWidth, y: base.y - dirX * halfWidth))
        context.closePath()
        context.fillPath()
        context.endTransparencyLayer()

        if let label, !label.isEmpty {
            // Place the caption beyond the tail, on the far side from the head.
            let size = labelSize(label)
            let reach = abs(dirX) * size.width / 2 + abs(dirY) * size.height / 2 + metrics.labelGap
            let center = CGPoint(x: tail.x - dirX * reach, y: tail.y - dirY * reach)
            context.setShadow(offset: .zero, blur: 0, color: nil)
            drawLabel(label, topLeft: CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2), color: color)
        }
    }

    /// A rounded backing in the mark colour with one line of text on it, its top-left corner at `topLeft`.
    func drawLabel(_ text: String, topLeft: CGPoint, color: MarkColor) {
        let line = makeLine(text, size: metrics.labelFontSize, color: color.onColorRGB)
        let bounds = LineBounds(line)
        let pad = metrics.labelPadding
        let backing = CGRect(x: topLeft.x, y: topLeft.y, width: bounds.width + pad.width * 2,
                             height: bounds.ascent + bounds.descent + pad.height * 2)
        context.saveGState()
        setShadow()
        context.setFillColor(srgb(color.rgb))
        context.addPath(CGPath(roundedRect: backing, cornerWidth: metrics.labelCornerRadius,
                               cornerHeight: metrics.labelCornerRadius, transform: nil))
        context.fillPath()
        context.restoreGState()
        drawLine(line, at: CGPoint(x: backing.minX + pad.width, y: backing.minY + pad.height + bounds.ascent))
    }

    func labelSize(_ text: String) -> CGSize {
        let bounds = LineBounds(makeLine(text, size: metrics.labelFontSize, color: RGB(1, 1, 1)))
        let pad = metrics.labelPadding
        return CGSize(width: bounds.width + pad.width * 2, height: bounds.ascent + bounds.descent + pad.height * 2)
    }

    func drawStep(_ number: Int, center: CGPoint, color: MarkColor) {
        let radius = metrics.stepDiameter / 2
        let disc = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        context.saveGState()
        setShadow()
        context.setFillColor(srgb(color.rgb))
        context.fillEllipse(in: disc)
        context.restoreGState()
        context.setStrokeColor(CGColor(gray: 1, alpha: 1))
        context.setLineWidth(metrics.stepRing)
        context.strokeEllipse(in: disc.insetBy(dx: metrics.stepRing / 2, dy: metrics.stepRing / 2))

        // Numbers past 99 shrink so they stay inside the disc.
        let text = String(number)
        let fontSize = metrics.stepFontSize * (text.count > 2 ? 0.75 : 1)
        let font = labelFont(size: fontSize)
        let line = makeLine(text, size: fontSize, color: color.onColorRGB)
        let bounds = LineBounds(line)
        // Centre the cap height, which is where digits sit.
        let baseline = center.y + CTFontGetCapHeight(font) / 2
        drawLine(line, at: CGPoint(x: center.x - bounds.width / 2, y: baseline))
    }

    func labelFont(size: Double) -> CTFont {
        CTFontCreateUIFontForLanguage(.emphasizedSystem, size, nil)
            ?? CTFontCreateWithName("Helvetica-Bold" as CFString, size, nil)
    }

    func makeLine(_ text: String, size: Double, color: RGB) -> CTLine {
        // One line only: newlines become spaces.
        let singleLine = text.replacingOccurrences(of: "\n", with: " ")
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): labelFont(size: size),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): srgb(color)
        ]
        return CTLineCreateWithAttributedString(NSAttributedString(string: singleLine, attributes: attributes))
    }

    /// Draws `line` with its baseline starting at `origin`, in the flipped context.
    func drawLine(_ line: CTLine, at origin: CGPoint) {
        context.saveGState()
        context.translateBy(x: origin.x, y: origin.y)
        context.scaleBy(x: 1, y: -1)
        context.textMatrix = .identity
        context.textPosition = .zero
        CTLineDraw(line, context)
        context.restoreGState()
    }
}

struct LineBounds {
    let width: Double
    let ascent: Double
    let descent: Double

    init(_ line: CTLine) {
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        width = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
        self.ascent = ascent
        self.descent = descent
    }
}
