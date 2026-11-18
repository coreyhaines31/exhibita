import CoreGraphics
import ExhibitCore

enum VisionGeometry {
    /// Converts a Vision box (normalized 0 to 1, origin bottom-left) to pixels of a `width` by `height` image
    /// with the origin top-left, as the document format uses.
    static func pixelRect(_ normalized: CGRect, width: Int, height: Int) -> PixelRect {
        let box = normalized.standardized
        let width = Double(width)
        let height = Double(height)
        return PixelRect(x: box.minX * width, y: (1 - box.maxY) * height, width: box.width * width,
                         height: box.height * height)
    }
}

/// The image's pixels, for shrinking OCR boxes to the ink inside them.
///
/// Vision pads its boxes by a few pixels and the padding varies. A box whose four corners share one colour sits
/// on a plain background, so rows and columns of that colour at its edges can be cut away. A box on anything
/// busier is left as it is.
struct InkGrid {
    let width: Int
    let height: Int
    private let bytes: [UInt8]

    /// Channel difference within which corner pixels count as the same background.
    static let backgroundTolerance = 24
    /// Channel difference beyond which a pixel counts as ink.
    static let inkThreshold = 40

    init?(_ image: CGImage) {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        self.width = width
        self.height = height
        bytes = buffer
    }

    /// `rect` shrunk to the ink inside it, or `rect` unchanged when its background is not plain or it holds no ink.
    func trimmed(_ rect: PixelRect) -> PixelRect {
        let box = rect.standardized
        let left = max(0, Int(box.minX.rounded(.down)))
        let top = max(0, Int(box.minY.rounded(.down)))
        let right = min(width, Int(box.maxX.rounded(.up)))
        let bottom = min(height, Int(box.maxY.rounded(.up)))
        guard right - left >= 3, bottom - top >= 3 else { return rect }

        let background = pixel(left, top)
        let corners = [pixel(right - 1, top), pixel(left, bottom - 1), pixel(right - 1, bottom - 1)]
        guard corners.allSatisfy({ $0.difference(background) <= Self.backgroundTolerance }) else { return rect }

        var inkLeft = right
        var inkRight = left - 1
        var inkTop = bottom
        var inkBottom = top - 1
        for row in top..<bottom {
            for column in left..<right where pixel(column, row).difference(background) > Self.inkThreshold {
                inkLeft = min(inkLeft, column)
                inkRight = max(inkRight, column)
                inkTop = min(inkTop, row)
                inkBottom = max(inkBottom, row)
            }
        }
        guard inkRight >= inkLeft, inkBottom >= inkTop else { return rect }
        return PixelRect(x: Double(inkLeft), y: Double(inkTop), width: Double(inkRight - inkLeft + 1),
                         height: Double(inkBottom - inkTop + 1))
    }

    private struct Color {
        let red: Int
        let green: Int
        let blue: Int

        func difference(_ other: Color) -> Int {
            max(abs(red - other.red), abs(green - other.green), abs(blue - other.blue))
        }
    }

    private func pixel(_ x: Int, _ y: Int) -> Color {
        let offset = (y * width + x) * 4
        return Color(red: Int(bytes[offset]), green: Int(bytes[offset + 1]), blue: Int(bytes[offset + 2]))
    }
}
