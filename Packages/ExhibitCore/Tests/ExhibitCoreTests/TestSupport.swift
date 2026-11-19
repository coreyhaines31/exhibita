import CoreGraphics
@testable import ExhibitCore
import ExhibitFixtures
import Foundation

func solidImage(width: Int, height: Int, gray: CGFloat) -> CGImage {
    makeImage(width: width, height: height) { context in
        context.setFillColor(CGColor(gray: gray, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    }
}

/// A fresh directory under the system temporary directory.
func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("ExhibitCoreTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// Tightly packed RGBA8 premultiplied pixels, top row first, in sRGB unless `space` names another (an image
/// already in that space is read without conversion).
struct Pixels: Equatable {
    let width: Int
    let height: Int
    let bytes: [UInt8]

    init(_ image: CGImage, space: CFString = CGColorSpace.sRGB) {
        width = image.width
        height = image.height
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        buffer.withUnsafeMutableBytes { raw in
            let context = CGContext(data: raw.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                                    bytesPerRow: image.width * 4, space: CGColorSpace(name: space)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            context?.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        bytes = buffer
    }

    func pixel(x: Int, y: Int) -> [UInt8] {
        let offset = (y * width + x) * 4
        return Array(bytes[offset..<offset + 4])
    }

    /// The pixels inside `rect` (whole pixels, clipped to the image), row by row.
    func region(_ rect: CGRect) -> [UInt8] {
        let clipped = rect.integral.intersection(CGRect(x: 0, y: 0, width: width, height: height))
        var out: [UInt8] = []
        for y in Int(clipped.minY)..<Int(clipped.maxY) {
            let start = (y * width + Int(clipped.minX)) * 4
            out.append(contentsOf: bytes[start..<start + Int(clipped.width) * 4])
        }
        return out
    }
}
