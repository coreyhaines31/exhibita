import CoreGraphics
import CoreText
import ExhibitCore
import Foundation

/// A made-up billing page drawn in code at 2x, with the targets the finder would report for it built from the
/// drawn text's own boxes. Example addresses and a made-up key only; nothing from the real screen.
struct EditorFixture {
    static let scale = 2.0
    let image: CGImage
    let targets: [Target]
    /// Pixel boxes by name: "email", "key", "update", "renews".
    let rects: [String: PixelRect]

    let emailID = UUID()
    let keyID = UUID()
    let updateID = UUID()

    init() {
        let page = Page(width: 620, height: 380, scale: Self.scale)
        page.fill(CGRect(x: 0, y: 0, width: 620, height: 380), 1)
        page.fill(CGRect(x: 0, y: 0, width: 620, height: 44), 0.96)
        page.fill(CGRect(x: 0, y: 44, width: 620, height: 1), 0.86)
        page.text("Northwind Console", x: 248, y: 14, size: 13, bold: true, gray: 0.45)
        page.text("Billing", x: 32, y: 66, size: 22, bold: true)
        page.text("Renews on December 1, 2026", x: 32, y: 104, size: 13, name: "renews")
        page.fill(CGRect(x: 32, y: 140, width: 556, height: 1), 0.9)
        page.text("Billing email", x: 32, y: 160, size: 11, gray: 0.45)
        page.text("jordan.lee@example.com", x: 32, y: 178, size: 14, name: "email")
        page.text("API key", x: 320, y: 160, size: 11, gray: 0.45)
        page.text("nw_live_7Hq2LmX9pT4vR8sK3d", x: 320, y: 178, size: 14, name: "key")
        page.fill(CGRect(x: 32, y: 222, width: 556, height: 1), 0.9)
        page.text("Plan", x: 32, y: 242, size: 11, gray: 0.45)
        page.text("Pro, 10 seats, $49/mo", x: 32, y: 260, size: 14)
        page.button("Update plan", frame: CGRect(x: 456, y: 310, width: 132, height: 36), name: "update")

        image = page.image()
        rects = page.rects
        let none = PixelRect(x: 0, y: 0, width: 0, height: 0)
        let email = rects["email"] ?? none
        let key = rects["key"] ?? none
        targets = [
            Target(kind: .text, text: "Renews on December 1, 2026", rect: rects["renews"] ?? none),
            Target(kind: .text, text: String(repeating: "•", count: 22), rect: email),
            Target(id: emailID, kind: .email, rect: email),
            Target(kind: .text, text: String(repeating: "•", count: 26), rect: key),
            Target(id: keyID, kind: .key, rect: key),
            Target(id: updateID, kind: .text, text: "Update plan", rect: rects["update"] ?? none)
        ]
    }

    func document(withTargets: Bool) -> CaptureDocument {
        CaptureDocument(size: PixelSize(width: image.width, height: image.height), scale: Self.scale,
                        source: CaptureSource(appName: "Safari", windowTitle: "Billing", capturedBy: .person),
                        targets: withTargets ? targets : [])
    }

    func center(_ name: String) -> PixelPoint {
        let rect = rects[name] ?? PixelRect(x: 0, y: 0, width: 0, height: 0)
        return PixelPoint(x: rect.midX, y: rect.midY)
    }
}

/// Draws in points with a top-left origin and records text boxes in pixels.
private final class Page {
    let context: CGContext
    let scale: Double
    private(set) var rects: [String: PixelRect] = [:]

    init(width: Int, height: Int, scale: Double) {
        let context = CGContext(data: nil, width: Int(Double(width) * scale), height: Int(Double(height) * scale),
                                bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let context else { fatalError("Couldn't make a fixture context") }
        context.translateBy(x: 0, y: CGFloat(Double(height) * scale))
        context.scaleBy(x: scale, y: -scale)
        self.context = context
        self.scale = scale
    }

    func fill(_ rect: CGRect, _ gray: CGFloat) {
        context.setFillColor(CGColor(gray: gray, alpha: 1))
        context.fill(rect)
    }

    func text(_ string: String, x: CGFloat, y: CGFloat, size: CGFloat, bold: Bool = false, gray: CGFloat = 0.12,
              white: Bool = false, name: String? = nil) {
        let font = CTFontCreateUIFontForLanguage(bold ? .emphasizedSystem : .system, size, nil)
        let color = white ? CGColor(gray: 1, alpha: 1) : CGColor(gray: gray, alpha: 1)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font as Any,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: attributes))
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        let width = CTLineGetTypographicBounds(line, &ascent, &descent, nil)
        context.saveGState()
        context.translateBy(x: x, y: y + ascent)
        context.scaleBy(x: 1, y: -1)
        context.textPosition = .zero
        CTLineDraw(line, context)
        context.restoreGState()
        if let name {
            rects[name] = PixelRect(x: x * scale, y: y * scale, width: width * scale, height: (ascent + descent) * scale)
        }
    }

    func button(_ title: String, frame: CGRect, name: String) {
        context.setFillColor(CGColor(red: 0, green: 0.48, blue: 1, alpha: 1))
        context.addPath(CGPath(roundedRect: frame, cornerWidth: 8, cornerHeight: 8, transform: nil))
        context.fillPath()
        text(title, x: frame.minX + 28, y: frame.minY + 9, size: 14, bold: true, white: true)
        rects[name] = PixelRect(x: frame.minX * scale, y: frame.minY * scale, width: frame.width * scale,
                                height: frame.height * scale)
    }

    func image() -> CGImage {
        guard let image = context.makeImage() else { fatalError("Couldn't make a fixture image") }
        return image
    }
}
