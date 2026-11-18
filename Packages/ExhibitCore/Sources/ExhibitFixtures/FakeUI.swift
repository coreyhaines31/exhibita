import CoreGraphics
import CoreText
import ExhibitCore
import Foundation

// Synthetic screenshots drawn in code, so tests and samples never depend on a real screen. Shared by the
// test targets; not a product.

/// An sRGB colour for fixtures, components from 0 to 1.
public struct Ink: Sendable, Equatable {
    public var r: Double
    public var g: Double
    public var b: Double

    public init(_ r: Double, _ g: Double, _ b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }

    var cgColor: CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: 1) }
}

/// An RGBA8 sRGB image drawn by `draw` in a context flipped to top-left coordinates.
public func makeImage(width: Int, height: Int, draw: (CGContext) -> Void) -> CGImage {
    guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        fatalError("Could not create a test context")
    }
    context.translateBy(x: 0, y: CGFloat(height))
    context.scaleBy(x: 1, y: -1)
    draw(context)
    guard let image = context.makeImage() else { fatalError("Could not make a test image") }
    return image
}

/// Draws a fake UI. Layouts are in points; `scale` multiplies them into pixels, as a Retina capture would.
public struct FakeUI {
    public let context: CGContext
    public let scale: Double
    /// Pixel rectangles of named elements, for placing marks and checking detection.
    public private(set) var rects: [String: PixelRect] = [:]

    public func fill(_ rect: CGRect, _ gray: Double) { fill(rect, Ink(gray, gray, gray)) }

    public func fill(_ rect: CGRect, _ color: Ink, radius: Double = 0) {
        context.setFillColor(color.cgColor)
        context.addPath(CGPath(roundedRect: scaled(rect), cornerWidth: radius * scale, cornerHeight: radius * scale,
                               transform: nil))
        context.fillPath()
    }

    public func stroke(_ rect: CGRect, _ color: Ink, radius: Double) {
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(scale)
        let inset = scaled(rect).insetBy(dx: scale / 2, dy: scale / 2)
        let corner = radius * scale
        context.addPath(CGPath(roundedRect: inset, cornerWidth: corner, cornerHeight: corner, transform: nil))
        context.strokePath()
    }

    public func dot(center: CGPoint, radius: Double, _ color: Ink) {
        context.setFillColor(color.cgColor)
        context.fillEllipse(in: scaled(CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2,
                                              height: radius * 2)))
    }

    /// Draws one line of text with its top-left at `at` and records its pixel box under `name`.
    public mutating func text(_ string: String, at: CGPoint, size: Double, bold: Bool = false,
                              _ color: Ink = Ink(0.11, 0.11, 0.12), name: String? = nil) {
        let line = Self.line(string, size: size * scale, bold: bold, color: color)
        let bounds = TypographicBounds(line)
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

    public mutating func button(_ title: String, frame: CGRect, primary: Bool, name: String) {
        if primary {
            fill(frame, Ink(0.0, 0.48, 1.0), radius: 7)
        } else {
            fill(frame, Ink(1, 1, 1), radius: 7)
            stroke(frame, Ink(0.82, 0.82, 0.85), radius: 7)
        }
        let size = 13.0
        let width = TypographicBounds(Self.line(title, size: size, bold: true, color: nil)).width
        text(title, at: CGPoint(x: frame.midX - width / 2, y: frame.midY - 8), size: size, bold: true,
             primary ? Ink(1, 1, 1) : Ink(0.11, 0.11, 0.12))
        rects[name] = PixelRect(x: frame.minX * scale, y: frame.minY * scale, width: frame.width * scale,
                                height: frame.height * scale)
    }

    public func scaled(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale)
    }

    public func point(_ x: Double, _ y: Double) -> PixelPoint { PixelPoint(x: x * scale, y: y * scale) }

    static func line(_ string: String, size: Double, bold: Bool, color: Ink?) -> CTLine {
        var attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String):
                CTFontCreateUIFontForLanguage(bold ? .emphasizedSystem : .system, size, nil)!
        ]
        if let color {
            attributes[NSAttributedString.Key(kCTForegroundColorAttributeName as String)] = color.cgColor
        }
        return CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: attributes))
    }
}

struct TypographicBounds {
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

public struct Fixture: @unchecked Sendable {
    public let image: CGImage
    public let rects: [String: PixelRect]
    public let scale: Double

    public func point(_ x: Double, _ y: Double) -> PixelPoint { PixelPoint(x: x * scale, y: y * scale) }
    public subscript(name: String) -> PixelRect { rects[name]! }
}

public func drawFixture(width: Double, height: Double, scale: Double, _ build: (inout FakeUI) -> Void) -> Fixture {
    var recorded: [String: PixelRect] = [:]
    let image = makeImage(width: Int(width * scale), height: Int(height * scale)) { context in
        var fake = FakeUI(context: context, scale: scale)
        build(&fake)
        recorded = fake.rects
    }
    return Fixture(image: image, rects: recorded, scale: scale)
}

/// A small settings card used by the golden tests.
public func goldenFixture(scale: Double) -> Fixture {
    drawFixture(width: 320, height: 200, scale: scale) { screen in
        screen.fill(CGRect(x: 0, y: 0, width: 320, height: 200), 0.96)
        screen.fill(CGRect(x: 12, y: 12, width: 296, height: 176), Ink(1, 1, 1), radius: 10)
        screen.stroke(CGRect(x: 12, y: 12, width: 296, height: 176), Ink(0.88, 0.88, 0.9), radius: 10)
        screen.text("Account settings", at: CGPoint(x: 28, y: 26), size: 15, bold: true, name: "heading")
        screen.text("Email", at: CGPoint(x: 28, y: 58), size: 11, Ink(0.45, 0.45, 0.5))
        screen.text("sam@example.com", at: CGPoint(x: 28, y: 74), size: 13, name: "email")
        screen.text("Plan", at: CGPoint(x: 220, y: 58), size: 11, Ink(0.45, 0.45, 0.5))
        screen.text("$49/mo", at: CGPoint(x: 220, y: 74), size: 13, bold: true, name: "price")
        screen.fill(CGRect(x: 28, y: 108, width: 190, height: 6), 0.86)
        screen.fill(CGRect(x: 28, y: 122, width: 150, height: 6), 0.86)
        screen.button("Save", frame: CGRect(x: 214, y: 144, width: 80, height: 28), primary: true, name: "save")
    }
}
