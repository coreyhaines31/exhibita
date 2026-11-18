import CoreGraphics
import CoreText
@testable import ExhibitCore
import Foundation

/// Synthetic screenshots drawn in code, so tests never depend on a real screen. Layouts are in points;
/// `scale` multiplies them into pixels, as a Retina capture would.
struct FakeUI {
    let context: CGContext
    let scale: Double
    /// Pixel rectangles of named elements, for placing marks.
    private(set) var rects: [String: PixelRect] = [:]

    func fill(_ rect: CGRect, _ gray: Double) { fill(rect, RGB(gray, gray, gray)) }

    func fill(_ rect: CGRect, _ color: RGB, radius: Double = 0) {
        context.setFillColor(srgb(color))
        context.addPath(CGPath(roundedRect: scaled(rect), cornerWidth: radius * scale, cornerHeight: radius * scale,
                               transform: nil))
        context.fillPath()
    }

    func stroke(_ rect: CGRect, _ color: RGB, radius: Double) {
        context.setStrokeColor(srgb(color))
        context.setLineWidth(scale)
        let inset = scaled(rect).insetBy(dx: scale / 2, dy: scale / 2)
        let corner = radius * scale
        context.addPath(CGPath(roundedRect: inset, cornerWidth: corner, cornerHeight: corner, transform: nil))
        context.strokePath()
    }

    func dot(center: CGPoint, radius: Double, _ color: RGB) {
        context.setFillColor(srgb(color))
        context.fillEllipse(in: scaled(CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2,
                                              height: radius * 2)))
    }

    /// Draws one line of text with its top-left at `at` and records its pixel box under `name`.
    mutating func text(_ string: String, at: CGPoint, size: Double, bold: Bool = false,
                       _ color: RGB = RGB(0.11, 0.11, 0.12), name: String? = nil) {
        let font = CTFontCreateUIFontForLanguage(bold ? .emphasizedSystem : .system, size * scale, nil)!
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): srgb(color)
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: attributes))
        let bounds = LineBounds(line)
        let origin = CGPoint(x: at.x * scale, y: at.y * scale)
        context.saveGState()
        context.translateBy(x: origin.x, y: origin.y + bounds.ascent)
        context.scaleBy(x: 1, y: -1)
        context.textMatrix = .identity
        context.textPosition = .zero
        CTLineDraw(line, context)
        context.restoreGState()
        if let name {
            rects[name] = PixelRect(x: origin.x, y: origin.y, width: bounds.width, height: bounds.ascent + bounds.descent)
        }
    }

    mutating func button(_ title: String, frame: CGRect, primary: Bool, name: String) {
        if primary {
            fill(frame, RGB(0.0, 0.48, 1.0), radius: 7)
        } else {
            fill(frame, RGB(1, 1, 1), radius: 7)
            stroke(frame, RGB(0.82, 0.82, 0.85), radius: 7)
        }
        let size = 13.0
        let probe = CTLineCreateWithAttributedString(NSAttributedString(string: title, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String):
                CTFontCreateUIFontForLanguage(.emphasizedSystem, size, nil)!
        ]))
        let width = LineBounds(probe).width
        text(title, at: CGPoint(x: frame.midX - width / 2, y: frame.midY - 8), size: size, bold: true,
             primary ? RGB(1, 1, 1) : RGB(0.11, 0.11, 0.12))
        rects[name] = PixelRect(x: frame.minX * scale, y: frame.minY * scale, width: frame.width * scale,
                                height: frame.height * scale)
    }

    func scaled(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale)
    }

    func point(_ x: Double, _ y: Double) -> PixelPoint { PixelPoint(x: x * scale, y: y * scale) }
}

struct Fixture {
    let image: CGImage
    let rects: [String: PixelRect]
    let scale: Double

    func point(_ x: Double, _ y: Double) -> PixelPoint { PixelPoint(x: x * scale, y: y * scale) }
    subscript(name: String) -> PixelRect { rects[name]! }
}

func drawFixture(width: Double, height: Double, scale: Double, _ build: (inout FakeUI) -> Void) -> Fixture {
    var recorded: [String: PixelRect] = [:]
    let image = makeImage(width: Int(width * scale), height: Int(height * scale)) { context in
        var fake = FakeUI(context: context, scale: scale)
        build(&fake)
        recorded = fake.rects
    }
    return Fixture(image: image, rects: recorded, scale: scale)
}

/// A small settings card used by the golden tests.
func goldenFixture(scale: Double) -> Fixture {
    drawFixture(width: 320, height: 200, scale: scale) { screen in
        screen.fill(CGRect(x: 0, y: 0, width: 320, height: 200), 0.96)
        screen.fill(CGRect(x: 12, y: 12, width: 296, height: 176), RGB(1, 1, 1), radius: 10)
        screen.stroke(CGRect(x: 12, y: 12, width: 296, height: 176), RGB(0.88, 0.88, 0.9), radius: 10)
        screen.text("Account settings", at: CGPoint(x: 28, y: 26), size: 15, bold: true, name: "heading")
        screen.text("Email", at: CGPoint(x: 28, y: 58), size: 11, RGB(0.45, 0.45, 0.5))
        screen.text("sam@example.com", at: CGPoint(x: 28, y: 74), size: 13, name: "email")
        screen.text("Plan", at: CGPoint(x: 220, y: 58), size: 11, RGB(0.45, 0.45, 0.5))
        screen.text("$49/mo", at: CGPoint(x: 220, y: 74), size: 13, bold: true, name: "price")
        screen.fill(CGRect(x: 28, y: 108, width: 190, height: 6), 0.86)
        screen.fill(CGRect(x: 28, y: 122, width: 150, height: 6), 0.86)
        screen.button("Save", frame: CGRect(x: 214, y: 144, width: 80, height: 28), primary: true, name: "save")
    }
}

/// One mark of each kind, placed on the golden fixture.
func goldenMark(_ kind: MarkKind, on fixture: Fixture) -> Mark {
    switch kind {
    case .arrow: .arrow(from: fixture.point(120, 168), to: fixture.point(208, 158), label: "Click")
    case .circle: .circle(fixture["price"])
    case .blur: .blur(fixture["email"])
    case .highlight: .highlight(fixture["heading"])
    case .text: .text("Looks good", at: fixture.point(186, 24), color: .blue)
    case .box: .box(fixture["save"], color: .green)
    case .step: .step(2, at: fixture.point(198, 158))
    }
}
