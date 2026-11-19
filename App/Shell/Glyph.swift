import AppKit

/// The menu bar glyph: the exhibit plate from the app icon, reduced to one ink. A window outline, cut clear around a
/// large solid disc with the A cut out of it (the A's counter stays ink). The plate's own small circled A could not be
/// read at 18 pt, so the disc is as large as the glyph allows. Drawn in code from the same geometry as mac-app-kit's
/// `Scripts/glyphs/glyphs.mjs` (`exhibit`), as an 18 pt template image. Agent captures blink the status item's
/// opacity, so the drawing has one state.
enum Glyph {
    static let discCenter = CGPoint(x: 11.5, y: 11.5)
    static let discRadius: CGFloat = 6
    /// The window is cut clear inside this radius, leaving a gap between it and the disc.
    static let clearRadius: CGFloat = 7.1

    static func image(size: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            let scale = rect.width / 18
            context.translateBy(x: rect.minX, y: rect.minY)
            context.scaleBy(x: scale, y: scale)
            context.setFillColor(NSColor.black.cgColor)
            context.setStrokeColor(NSColor.black.cgColor)

            // Window outline, clipped clear around the disc (even-odd: the whole glyph minus the clearance circle).
            context.saveGState()
            let clip = CGMutablePath()
            clip.addRect(CGRect(x: -1, y: -1, width: 20, height: 20))
            clip.addEllipse(in: circle(radius: clearRadius))
            context.addPath(clip)
            context.clip(using: .evenOdd)
            context.addPath(CGPath(roundedRect: CGRect(x: 1.75, y: 1.75, width: 10, height: 7.5),
                                   cornerWidth: 1.3, cornerHeight: 1.3, transform: nil))
            context.setLineWidth(1.5)
            context.strokePath()
            context.restoreGState()

            // Disc and A in one even-odd fill: the A's outline cut out, its counter stays ink.
            let disc = CGMutablePath()
            disc.addEllipse(in: circle(radius: discRadius))
            addLetterA(to: disc, in: CGRect(x: 8, y: 8.2, width: 7, height: 6.6))
            context.addPath(disc)
            context.fillPath(using: .evenOdd)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = Brand.name
        return image
    }

    private static func circle(radius: CGFloat) -> CGRect {
        CGRect(x: discCenter.x - radius, y: discCenter.y - radius, width: radius * 2, height: radius * 2)
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
