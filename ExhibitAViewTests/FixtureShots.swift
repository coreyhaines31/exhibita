import CoreGraphics
import Foundation

/// Made-up screenshots drawn in code for history thumbnails. Blocks only, no text, nothing from the real screen.
enum FixtureShots {
    static func browser(dark: Bool = false) -> CGImage {
        draw(width: 1600, height: 1000) { context, size in
            fill(context, CGRect(origin: .zero, size: size), gray: dark ? 0.12 : 0.97)
            fill(context, CGRect(x: 0, y: 0, width: size.width, height: 90), gray: dark ? 0.2 : 0.9)
            for (index, red) in [0.93, 0.98, 0.35].enumerated() {
                context.setFillColor(CGColor(red: red, green: index == 2 ? 0.78 : 0.6, blue: 0.3, alpha: 1))
                context.fillEllipse(in: CGRect(x: 30 + index * 40, y: 30, width: 26, height: 26))
            }
            fill(context, CGRect(x: 300, y: 25, width: 1000, height: 40), gray: dark ? 0.28 : 1, radius: 10)
            fill(context, CGRect(x: 0, y: 90, width: 300, height: size.height - 90), gray: dark ? 0.16 : 0.94)
            for row in 0..<6 {
                fill(context, CGRect(x: 360, y: 160 + row * 120, width: row.isMultiple(of: 2) ? 900 : 700, height: 36),
                     gray: dark ? 0.35 : 0.82, radius: 6)
            }
            context.setFillColor(CGColor(red: 0.18, green: 0.39, blue: 0.83, alpha: 1))
            context.fill(CGRect(x: 1200, y: 820, width: 260, height: 70))
        }
    }

    static func terminal() -> CGImage {
        draw(width: 1400, height: 900) { context, size in
            fill(context, CGRect(origin: .zero, size: size), gray: 0.08)
            fill(context, CGRect(x: 0, y: 0, width: size.width, height: 60), gray: 0.18)
            for row in 0..<14 {
                let width = 200 + (row * 173) % 900
                context.setFillColor(row % 5 == 0 ? CGColor(red: 0.36, green: 0.76, blue: 0.48, alpha: 1)
                                                  : CGColor(gray: 0.7, alpha: 1))
                context.fill(CGRect(x: 40, y: 100 + row * 52, width: width, height: 22))
            }
        }
    }

    static func document() -> CGImage {
        draw(width: 900, height: 1100) { context, size in
            fill(context, CGRect(origin: .zero, size: size), gray: 0.99)
            context.setFillColor(CGColor(red: 0.98, green: 0.85, blue: 0.3, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: size.width, height: 70))
            fill(context, CGRect(x: 60, y: 130, width: 500, height: 44), gray: 0.2)
            for row in 0..<12 {
                fill(context, CGRect(x: 60, y: 220 + row * 64, width: row % 4 == 3 ? 420 : 780, height: 20), gray: 0.6)
            }
        }
    }

    private static func fill(_ context: CGContext, _ rect: CGRect, gray: CGFloat, radius: CGFloat = 0) {
        context.setFillColor(CGColor(gray: gray, alpha: 1))
        if radius > 0 {
            context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
            context.fillPath()
        } else {
            context.fill(rect)
        }
    }

    /// Draws with a top-left origin, as screenshots read.
    private static func draw(width: Int, height: Int, _ body: (CGContext, CGSize) -> Void) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let context else { fatalError("Couldn't make a fixture context") }
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        body(context, CGSize(width: width, height: height))
        guard let image = context.makeImage() else { fatalError("Couldn't make a fixture image") }
        return image
    }
}
