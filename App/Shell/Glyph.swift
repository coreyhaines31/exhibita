import AppKit

/// The menu bar glyph: four crop corners around an evidence dot, drawn in code as an 18 pt template image.
/// mac-app-kit's `Scripts/glyphs/` will supply the family glyph; it replaces the drawing in `image(size:)` and
/// nothing else changes.
enum Glyph {
    static func image(size: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { rect in
            let scale = rect.width / 18
            NSColor.black.setStroke()
            NSColor.black.setFill()
            let corners = NSBezierPath()
            corners.lineWidth = 1.5 * scale
            corners.lineCapStyle = .round
            corners.lineJoinStyle = .round
            let inset = 2.5 * scale
            let arm = 4.5 * scale
            let far = rect.width - inset
            for (x, y, dx, dy) in [(inset, inset, 1.0, 1.0), (far, inset, -1.0, 1.0),
                                   (inset, far, 1.0, -1.0), (far, far, -1.0, -1.0)] {
                corners.move(to: NSPoint(x: x, y: y + dy * arm))
                corners.line(to: NSPoint(x: x, y: y))
                corners.line(to: NSPoint(x: x + dx * arm, y: y))
            }
            corners.stroke()
            let dot = 4 * scale
            NSBezierPath(ovalIn: NSRect(x: rect.midX - dot / 2, y: rect.midY - dot / 2, width: dot, height: dot)).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = Brand.name
        return image
    }
}
