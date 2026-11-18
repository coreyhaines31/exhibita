import Foundation

/// One capture: the original image (stored beside this record), what was found in it, and the marks on it.
///
/// Coordinates everywhere are pixels of the original image, origin top-left. See `docs/format.md`.
public struct CaptureDocument: Codable, Sendable, Equatable, Identifiable {
    /// The format this version of ExhibitCore reads and writes.
    public static let currentFormatVersion = 1

    public var formatVersion: Int
    public var id: UUID
    /// Stored to the whole second.
    public var createdAt: Date
    /// Pixel size of the original image.
    public var size: PixelSize
    /// Backing scale of the display it came from (2 on Retina). Mark strokes scale with it.
    public var scale: Double
    public var source: CaptureSource?
    public var targets: [Target]
    /// In drawing order. Blur marks are always applied first, under everything else.
    public var marks: [Mark]

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        size: PixelSize,
        scale: Double = 1,
        source: CaptureSource? = nil,
        targets: [Target] = [],
        marks: [Mark] = []
    ) {
        formatVersion = Self.currentFormatVersion
        self.id = id
        self.createdAt = Date(timeIntervalSince1970: createdAt.timeIntervalSince1970.rounded(.down))
        self.size = size
        self.scale = scale
        self.source = source
        self.targets = targets
        self.marks = marks
    }
}

/// Where a capture came from.
public struct CaptureSource: Codable, Sendable, Equatable {
    public var appName: String?
    public var windowTitle: String?
    public var capturedBy: CapturedBy?

    public init(appName: String? = nil, windowTitle: String? = nil, capturedBy: CapturedBy? = nil) {
        self.appName = appName
        self.windowTitle = windowTitle
        self.capturedBy = capturedBy
    }
}

/// Who asked for the capture. Agent captures are tagged in history.
public enum CapturedBy: String, Codable, Sendable {
    case person
    case agent
}
