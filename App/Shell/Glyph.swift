import AppKit

/// The menu bar glyph: the evidence tag from the app icon, solid, with its eyelet and the A cut out and the string
/// looped above. Drawn in code from the same geometry as mac-app-kit's `Scripts/glyphs/glyphs.mjs` (`exhibit`), as
/// an 18 pt template image. Agent captures blink the status item's opacity, so the drawing has one state.
enum Glyph {
    static func image(size: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            let scale = rect.width / 18
            context.translateBy(x: rect.minX, y: rect.minY)
            context.scaleBy(x: scale, y: scale)
            context.setFillColor(NSColor.black.cgColor)
            context.setStrokeColor(NSColor.black.cgColor)

            // Tag, eyelet and A in one even-odd fill: the eyelet and the A's outline cut out, its counter stays ink.
            let tag = CGMutablePath()
            tag.move(to: CGPoint(x: 3.1, y: 8.1))
            tag.addLine(to: CGPoint(x: 6.1, y: 4.7))
            tag.addLine(to: CGPoint(x: 11.9, y: 4.7))
            tag.addLine(to: CGPoint(x: 14.9, y: 8.1))
            tag.addLine(to: CGPoint(x: 14.9, y: 16.1))
            tag.addQuadCurve(to: CGPoint(x: 13.7, y: 17.3), control: CGPoint(x: 14.9, y: 17.3))
            tag.addLine(to: CGPoint(x: 4.3, y: 17.3))
            tag.addQuadCurve(to: CGPoint(x: 3.1, y: 16.1), control: CGPoint(x: 3.1, y: 17.3))
            tag.closeSubpath()
            tag.addEllipse(in: CGRect(x: 9 - 1.15, y: 7.25 - 1.15, width: 2.3, height: 2.3))
            addLetterA(to: tag, in: CGRect(x: 5.25, y: 9.4, width: 7.5, height: 6.9))
            context.addPath(tag)
            context.fillPath(using: .evenOdd)

            let string = CGMutablePath()
            string.move(to: CGPoint(x: 8.3, y: 5.6))
            string.addCurve(to: CGPoint(x: 9.4, y: 1),
                            control1: CGPoint(x: 7, y: 3.6), control2: CGPoint(x: 7.3, y: 1.1))
            string.addCurve(to: CGPoint(x: 9.7, y: 5.6),
                            control1: CGPoint(x: 11.6, y: 0.9), control2: CGPoint(x: 12.1, y: 3.4))
            context.addPath(string)
            context.setLineWidth(1.15)
            context.setLineCap(.round)
            context.strokePath()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = Brand.name
        return image
    }

    /// A bold condensed capital A in `box`: the outline, then the counter as a second subpath.
    private static func addLetterA(to path: CGMutablePath, in box: CGRect) {
        func point(_ u: CGFloat, _ v: CGFloat) -> CGPoint {
            CGPoint(x: box.minX + u * box.width, y: box.minY + v * box.height)
        }
        path.addLines(between: [point(0, 1), point(0.34, 0), point(0.66, 0), point(1, 1),
                                point(0.72, 1), point(0.65, 0.78), point(0.35, 0.78), point(0.28, 1)])
        path.closeSubpath()
        path.addLines(between: [point(0.41, 0.56), point(0.5, 0.24), point(0.59, 0.56)])
        path.closeSubpath()
    }
}
