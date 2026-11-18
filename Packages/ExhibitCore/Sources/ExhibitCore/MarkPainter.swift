import CoreGraphics

/// Draws one mark at a time into a context already flipped to top-left pixel coordinates.
struct MarkPainter {
    let context: CGContext
    let metrics: MarkMetrics

    func draw(_ mark: Mark) {
        context.saveGState()
        defer { context.restoreGState() }
        switch mark.kind {
        case .arrow:
            if case let .line(from, to) = mark.geometry {
                drawArrow(from: from.cgPoint, to: to.cgPoint, color: mark.style.color, label: mark.style.label)
            }
        case .circle:
            drawCircle(mark.bounds.cgRect, color: mark.style.color)
        case .highlight:
            drawHighlight(mark.bounds.cgRect, color: mark.style.color)
        case .text:
            let origin = mark.bounds.cgRect.origin
            drawLabel(mark.style.label ?? "", topLeft: origin, color: mark.style.color)
        case .box:
            drawBox(mark.bounds.cgRect, color: mark.style.color)
        case .step:
            let rect = mark.bounds.cgRect
            drawStep(mark.style.stepNumber ?? 1, center: CGPoint(x: rect.midX, y: rect.midY), color: mark.style.color)
        case .blur:
            // Applied to the pixels before any drawing; see `Redaction`.
            break
        }
    }

    /// A soft drop shadow under the next drawing, so marks stand off busy screenshots.
    func setShadow() {
        // Shadow offsets are in device space, where positive y is up; negative moves the shadow down.
        context.setShadow(offset: CGSize(width: 0, height: -metrics.shadowOffset), blur: metrics.shadowBlur,
                          color: CGColor(gray: 0, alpha: 0.35))
    }

    func drawCircle(_ rect: CGRect, color: MarkColor) {
        // An ellipse through the corners of `rect` is `rect` scaled by the square root of 2; pad beyond that.
        let radiusX = rect.width / 2 * 2.0.squareRoot() + metrics.circlePadding
        let radiusY = rect.height / 2 * 2.0.squareRoot() + metrics.circlePadding
        let ellipse = CGRect(x: rect.midX - radiusX, y: rect.midY - radiusY, width: radiusX * 2, height: radiusY * 2)
        setShadow()
        context.setStrokeColor(srgb(color.rgb))
        context.setLineWidth(metrics.stroke)
        context.strokeEllipse(in: ellipse)
    }

    func drawBox(_ rect: CGRect, color: MarkColor) {
        let padded = rect.insetBy(dx: -metrics.boxPadding, dy: -metrics.boxPadding)
        let radius = min(metrics.boxCornerRadius, padded.width / 2, padded.height / 2)
        setShadow()
        context.setStrokeColor(srgb(color.rgb))
        context.setLineWidth(metrics.stroke)
        context.addPath(CGPath(roundedRect: padded, cornerWidth: radius, cornerHeight: radius, transform: nil))
        context.strokePath()
    }

    func drawHighlight(_ rect: CGRect, color: MarkColor) {
        let pad = metrics.highlightPadding
        let padded = rect.insetBy(dx: -pad.width, dy: -pad.height)
        let radius = min(metrics.highlightCornerRadius, padded.width / 2, padded.height / 2)
        context.setBlendMode(.multiply)
        context.setFillColor(srgb(color.markerRGB))
        context.addPath(CGPath(roundedRect: padded, cornerWidth: radius, cornerHeight: radius, transform: nil))
        context.fillPath()
    }
}
