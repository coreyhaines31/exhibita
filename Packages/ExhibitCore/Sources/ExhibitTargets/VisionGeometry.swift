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
/// Vision pads its boxes by a varying number of pixels, sometimes past the edge of a button. The colours along
/// a box's border are its background (a button and the window behind it, say); every other pixel is ink, and
/// the box shrinks to the ink.
struct InkGrid {
    let width: Int
    let height: Int
    private let bytes: [UInt8]

    /// Channel difference within which a pixel matches a background colour. Anything further from every
    /// background colour is ink, including antialiased glyph edges. Small, so white text next to a light gray
    /// window still reads as ink.
    static let tolerance = 12
    /// Share of the border a colour must cover to count as background.
    static let backgroundShare = 0.03

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

    /// `rect` shrunk to the ink inside it, or `rect` unchanged when it is tiny, has no clear background or holds
    /// no ink.
    func trimmed(_ rect: PixelRect) -> PixelRect {
        let box = rect.standardized
        let left = max(0, Int(box.minX.rounded(.down)))
        let top = max(0, Int(box.minY.rounded(.down)))
        let right = min(width, Int(box.maxX.rounded(.up)))
        let bottom = min(height, Int(box.maxY.rounded(.up)))
        guard right - left >= 3, bottom - top >= 3 else { return rect }

        let backgrounds = backgroundColors(left: left, top: top, right: right, bottom: bottom)
        guard !backgrounds.isEmpty else { return rect }
        let isInk = { (color: Color) in
            backgrounds.allSatisfy { $0.difference(color) > Self.tolerance }
        }
        var inkLeft = right
        var inkRight = left - 1
        var inkTop = bottom
        var inkBottom = top - 1
        for row in top..<bottom {
            for column in left..<right where isInk(pixel(column, row)) {
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

    /// Colours that cover at least `backgroundShare` of the box's border and appear on at least two of its sides,
    /// grouped within `tolerance`. A glyph the box cuts through usually touches one side only.
    private func backgroundColors(left: Int, top: Int, right: Int, bottom: Int) -> [Color] {
        let sides: [[Color]] = [
            (left..<right).map { pixel($0, top) },
            (left..<right).map { pixel($0, bottom - 1) },
            (top..<bottom).map { pixel(left, $0) },
            (top..<bottom).map { pixel(right - 1, $0) }
        ]
        var groups: [ColorGroup] = []
        for (side, colors) in sides.enumerated() {
            for color in colors {
                if let index = groups.firstIndex(where: { $0.color.difference(color) <= Self.tolerance }) {
                    groups[index].count += 1
                    groups[index].sides.insert(side)
                } else if groups.count < 32 {
                    groups.append(ColorGroup(color: color, count: 1, sides: [side]))
                }
            }
        }
        let needed = Double(sides.map(\.count).reduce(0, +)) * Self.backgroundShare
        return groups.filter { Double($0.count) >= needed && $0.sides.count >= 2 }.map(\.color)
    }

    private struct ColorGroup {
        let color: Color
        var count: Int
        var sides: Set<Int>
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
