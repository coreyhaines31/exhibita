import CoreGraphics
import ExhibitCore
import Foundation
import ImageIO

/// History: every capture as a `CaptureBundle` in one directory, by default
/// `~/Library/Application Support/Exhibit A/Captures`. The directory is excluded from Time Machine and marked
/// so Spotlight does not index it. Every write is atomic, so a crash never leaves half a capture.
///
/// Synchronous file work: call it off the main thread. The directory is injected so tests use a temporary one.
public struct CaptureStore: Sendable {
    public let directory: URL

    /// Spotlight skips a directory holding this file.
    public static let neverIndexFileName = ".metadata_never_index"

    public init(directory: URL) {
        self.directory = directory
    }

    /// `~/Library/Application Support/Exhibit A/Captures`.
    public static func defaultDirectory() throws -> URL {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                  appropriateFor: nil, create: true)
        return support.appendingPathComponent("Exhibit A", isDirectory: true)
            .appendingPathComponent("Captures", isDirectory: true)
    }

    /// Creates the directory if needed, excludes it from backups and from Spotlight. Safe to call every launch.
    public func prepare() throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var url = directory
        try url.setResourceValues(values)
        let marker = directory.appendingPathComponent(Self.neverIndexFileName)
        if !fileManager.fileExists(atPath: marker.path) {
            try Data().write(to: marker, options: .atomic)
        }
    }

    /// Whether the directory is excluded from Time Machine.
    public var isExcludedFromBackup: Bool {
        (try? directory.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup) == true
    }

    // MARK: - Writing

    /// Saves a new capture and returns its history entry. `id` is the capture's stable id.
    @discardableResult
    public func create(image: CGImage, scale: Double, capturedBy: CapturedBy, appName: String? = nil,
                       windowTitle: String? = nil, id: UUID = UUID(), now: Date = Date()) throws -> HistoryItem {
        try prepare()
        let document = CaptureDocument(
            id: id, createdAt: now, size: PixelSize(width: image.width, height: image.height), scale: scale,
            source: CaptureSource(appName: appName, windowTitle: windowTitle, capturedBy: capturedBy)
        )
        let url = try CaptureBundle.save(document, original: image, in: directory)
        return HistoryItem(id: document.id, createdAt: document.createdAt, size: document.size, scale: scale,
                           capturedBy: capturedBy, appName: appName, windowTitle: windowTitle, url: url)
    }

    /// Saves a changed document (marks, targets). Only `document.json` is rewritten, atomically, so call it on
    /// every change.
    public func save(_ document: CaptureDocument) throws {
        try CaptureBundle.saveDocument(document, to: url(for: document.id))
    }

    /// Stores the targets found after capture, and adds `marks` (an agent capture's auto-blur). Marks already on
    /// the document are kept.
    public func updateTargets(_ targets: [Target], adding marks: [Mark] = [], for id: UUID) throws {
        var document = try load(id).document
        document.targets = targets
        document.marks += marks
        try save(document)
    }

    // MARK: - Reading

    public func url(for id: UUID) -> URL {
        CaptureBundle.url(for: id, in: directory)
    }

    /// Where an agent capture's flattened copy goes: `<id>.png` beside the bundle. `exhibit` commands on the
    /// capture write `<id>-marked.png` and up beside it too. All of them go when the capture is deleted.
    public func exportURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).png")
    }

    public func load(_ id: UUID) throws -> CaptureBundle.Loaded {
        try CaptureBundle.load(from: url(for: id))
    }

    /// Every readable capture, newest first. Bundles still being written, unreadable ones and ones from a newer
    /// format version are left out (and left alone on disk).
    public func list() -> [HistoryItem] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return bundleURLs().compactMap { url -> HistoryItem? in
            guard let data = try? Data(contentsOf: url.appendingPathComponent(CaptureBundle.documentFileName)),
                  let header = try? decoder.decode(HistoryHeader.self, from: data),
                  header.formatVersion <= CaptureDocument.currentFormatVersion,
                  url.lastPathComponent == "\(header.id.uuidString).\(CaptureBundle.fileExtension)"
            else { return nil }
            return header.item(url: url)
        }
        .sorted { lhs, rhs in
            lhs.createdAt == rhs.createdAt ? lhs.id.uuidString < rhs.id.uuidString : lhs.createdAt > rhs.createdAt
        }
    }

    /// A small image for the history list, decoded at most `maxPixelSize` on its long side.
    public func thumbnail(for id: UUID, maxPixelSize: Int) -> CGImage? {
        let original = url(for: id).appendingPathComponent(CaptureBundle.originalFileName)
        guard let source = CGImageSourceCreateWithURL(original as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    // MARK: - Deleting

    /// Deletes one capture's files. Deleting a capture that is already gone is not an error.
    /// Its flattened exports beside it (`<id>.png`, `<id>-marked.png`, `<id>-marked-2.png`, ...) go with it.
    public func delete(_ id: UUID) throws {
        for export in exportURLs(of: id) {
            try? FileManager.default.removeItem(at: export)
        }
        let url = url(for: id)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    /// Deletes every capture, including half-written ones. Returns how many captures were deleted.
    @discardableResult
    public func purgeAll() throws -> Int {
        let captures = bundleURLs()
        for url in captures + stagingURLs() + exportURLs(of: nil) {
            try FileManager.default.removeItem(at: url)
        }
        return captures.count
    }

    /// Deletes captures past `policy`'s period, and staging directories left by a crash. Returns the ids deleted.
    @discardableResult
    public func sweep(policy: RetentionPolicy, now: Date = Date()) throws -> [UUID] {
        for url in stagingURLs() {
            try? FileManager.default.removeItem(at: url)
        }
        let expired = list().filter { policy.isExpired(createdAt: $0.createdAt, now: now) }
        for item in expired {
            try delete(item.id)
        }
        return expired.map(\.id)
    }

    /// Call after a capture is exported. Under `.discardOnExport` the capture is deleted; returns whether it was.
    @discardableResult
    public func didExport(_ id: UUID, policy: RetentionPolicy) throws -> Bool {
        guard policy.discardsOnExport else { return false }
        try delete(id)
        return true
    }

    // MARK: - Directory listing

    private func contents() -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
    }

    private func bundleURLs() -> [URL] {
        contents().filter { url in
            url.pathExtension == CaptureBundle.fileExtension && !url.lastPathComponent.hasPrefix(".")
                && UUID(uuidString: url.deletingPathExtension().lastPathComponent) != nil
        }
    }

    /// Flattened PNGs named after a capture id, for one capture or for any.
    private func exportURLs(of id: UUID?) -> [URL] {
        contents().filter { url in
            guard url.pathExtension.lowercased() == "png" else { return false }
            let name = url.deletingPathExtension().lastPathComponent
            guard name.range(of: #"^[0-9A-Fa-f-]{36}(-marked(-[0-9]+)?)?$"#, options: .regularExpression) != nil,
                  let found = UUID(uuidString: String(name.prefix(36))) else { return false }
            return id == nil || found == id
        }
    }

    private func stagingURLs() -> [URL] {
        contents().filter { $0.lastPathComponent.hasPrefix(".") && $0.pathExtension == "partial" }
    }
}
