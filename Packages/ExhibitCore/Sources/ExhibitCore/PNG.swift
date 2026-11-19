import CoreGraphics
import Foundation
import ImageIO

/// PNG encoding and decoding through ImageIO.
public enum PNG {
    private static var pngType: CFString { "public.png" as CFString }

    /// Encodes one image as a PNG with no metadata, thumbnails or auxiliary images.
    public static func encode(_ image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, pngType, 1, nil) else {
            throw ExhibitError.imageEncodingFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw ExhibitError.imageEncodingFailed }
        return try stripMetadata(data as Data)
    }

    /// Chunks an exported PNG may keep: image data and colour information. ImageIO adds an `eXIf` chunk
    /// (pixel dimensions and colour space) that carries nothing useful, so everything else is dropped.
    static let keptChunks: Set<String> = ["IHDR", "PLTE", "IDAT", "IEND", "sRGB", "iCCP", "gAMA", "cHRM", "pHYs"]

    /// Rewrites a PNG keeping only `keptChunks`, in order. Each chunk's bytes, CRC included, are copied unchanged.
    static func stripMetadata(_ png: Data) throws -> Data {
        let bytes = [UInt8](png)
        let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        guard bytes.count >= 8, Array(bytes[0..<8]) == signature else { throw ExhibitError.imageEncodingFailed }
        var output = signature
        var offset = 8
        while offset + 12 <= bytes.count {
            let length = bytes[offset..<offset + 4].reduce(0) { $0 << 8 | Int($1) }
            let end = offset + 12 + length
            guard end <= bytes.count else { throw ExhibitError.imageEncodingFailed }
            let type = String(bytes: bytes[offset + 4..<offset + 8], encoding: .ascii) ?? ""
            if keptChunks.contains(type) { output.append(contentsOf: bytes[offset..<end]) }
            offset = end
        }
        guard offset == bytes.count else { throw ExhibitError.imageEncodingFailed }
        return Data(output)
    }

    /// Decodes the first image in `data`. Accepts any format ImageIO reads, not only PNG.
    public static func decode(_ data: Data) throws -> CGImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw ExhibitError.imageDecodingFailed
        }
        return image
    }
}

/// Errors from reading, writing and rendering captures. Messages never include image or document contents.
public enum ExhibitError: Error, Equatable, CustomStringConvertible {
    /// The bundle was written by a newer version of Exhibit A.
    case unsupportedFormatVersion(found: Int, supported: Int)
    case missingFile(String)
    case imageDecodingFailed
    case imageEncodingFailed
    /// The original image's pixel size differs from the document's `size`.
    case sizeMismatch(document: PixelSize, image: PixelSize)
    case renderFailed

    public var description: String {
        switch self {
        case let .unsupportedFormatVersion(found, supported):
            "This capture uses format version \(found); this version of Exhibit A reads up to \(supported). "
                + "Update Exhibit A to open it."
        case .missingFile(let name):
            "The capture bundle is missing \(name)."
        case .imageDecodingFailed:
            "The image could not be read."
        case .imageEncodingFailed:
            "The image could not be written as a PNG."
        case let .sizeMismatch(document, image):
            "The original image is \(image.width)x\(image.height) pixels "
                + "but the document says \(document.width)x\(document.height)."
        case .renderFailed:
            "The image could not be rendered."
        }
    }
}
