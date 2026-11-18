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
        return data as Data
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
