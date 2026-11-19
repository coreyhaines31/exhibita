import CoreGraphics
import Foundation

/// The on-disk form of a capture: a directory `<uuid>.exhibit/` holding `original.png` and `document.json`.
///
/// Every file is written atomically, and a new bundle appears under its final name only once complete.
public enum CaptureBundle {
    public static let fileExtension = "exhibit"
    public static let originalFileName = "original.png"
    public static let documentFileName = "document.json"

    /// A capture read back from disk.
    public struct Loaded {
        public var document: CaptureDocument
        public var original: CGImage
        public var url: URL
    }

    /// The bundle directory for a document inside `directory`.
    public static func url(for id: UUID, in directory: URL) -> URL {
        directory.appendingPathComponent("\(id.uuidString).\(fileExtension)", isDirectory: true)
    }

    /// Writes a complete bundle (original and document) into `directory` and returns the bundle's URL.
    /// The bundle is always assembled beside its destination and swapped in whole, so an existing bundle with
    /// the same id is replaced by the new pair or left as it was, never half updated.
    @discardableResult
    public static func save(_ document: CaptureDocument, original: CGImage, in directory: URL) throws -> URL {
        let imageSize = PixelSize(width: original.width, height: original.height)
        guard imageSize == document.size else { throw ExhibitError.sizeMismatch(document: document.size, image: imageSize) }
        let png = try PNG.encode(original)
        let json = try encode(document)
        let fileManager = FileManager.default
        let destination = url(for: document.id, in: directory)

        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let stagingName = ".\(document.id.uuidString).\(fileExtension).partial"
        let staging = directory.appendingPathComponent(stagingName, isDirectory: true)
        if fileManager.fileExists(atPath: staging.path) { try fileManager.removeItem(at: staging) }
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: false)
        do {
            try png.write(to: staging.appendingPathComponent(originalFileName), options: .atomic)
            try json.write(to: staging.appendingPathComponent(documentFileName), options: .atomic)
            if fileManager.fileExists(atPath: destination.path) {
                _ = try fileManager.replaceItemAt(destination, withItemAt: staging)
            } else {
                try fileManager.moveItem(at: staging, to: destination)
            }
        } catch {
            try? fileManager.removeItem(at: staging)
            throw error
        }
        return destination
    }

    /// Rewrites only `document.json` in an existing bundle, for example after marks change.
    public static func saveDocument(_ document: CaptureDocument, to bundleURL: URL) throws {
        guard FileManager.default.fileExists(atPath: bundleURL.appendingPathComponent(originalFileName).path) else {
            throw ExhibitError.missingFile(originalFileName)
        }
        try encode(document).write(to: bundleURL.appendingPathComponent(documentFileName), options: .atomic)
    }

    /// Reads a bundle. Throws `ExhibitError.unsupportedFormatVersion` for a bundle from a newer version.
    public static func load(from bundleURL: URL) throws -> Loaded {
        let documentURL = bundleURL.appendingPathComponent(documentFileName)
        let originalURL = bundleURL.appendingPathComponent(originalFileName)
        guard let json = try? Data(contentsOf: documentURL) else { throw ExhibitError.missingFile(documentFileName) }
        let document = try decode(json)
        guard let png = try? Data(contentsOf: originalURL) else { throw ExhibitError.missingFile(originalFileName) }
        let original = try PNG.decode(png)
        let imageSize = PixelSize(width: original.width, height: original.height)
        guard imageSize == document.size else { throw ExhibitError.sizeMismatch(document: document.size, image: imageSize) }
        return Loaded(document: document, original: original, url: bundleURL)
    }

    /// `document.json` bytes: pretty-printed, sorted keys, ISO 8601 dates. Same document, same bytes.
    public static func encode(_ document: CaptureDocument) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(document)
    }

    /// Decodes `document.json`, checking `formatVersion` before anything else.
    public static func decode(_ data: Data) throws -> CaptureDocument {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let header = try decoder.decode(VersionHeader.self, from: data)
        guard header.formatVersion <= CaptureDocument.currentFormatVersion else {
            throw ExhibitError.unsupportedFormatVersion(found: header.formatVersion,
                                                        supported: CaptureDocument.currentFormatVersion)
        }
        return try decoder.decode(CaptureDocument.self, from: data)
    }

    private struct VersionHeader: Decodable {
        var formatVersion: Int
    }
}
