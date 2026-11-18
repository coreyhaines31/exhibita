import ExhibitCore
import Foundation

/// One capture in history, read from `document.json` alone: no image is decoded to list history.
public struct HistoryItem: Sendable, Equatable, Identifiable {
    public var id: UUID
    public var createdAt: Date
    public var size: PixelSize
    public var scale: Double
    public var capturedBy: CapturedBy
    public var appName: String?
    public var windowTitle: String?
    public var markCount: Int
    public var targetCount: Int
    /// The bundle directory.
    public var url: URL

    public init(id: UUID, createdAt: Date, size: PixelSize, scale: Double, capturedBy: CapturedBy,
                appName: String? = nil, windowTitle: String? = nil, markCount: Int = 0, targetCount: Int = 0,
                url: URL) {
        self.id = id
        self.createdAt = createdAt
        self.size = size
        self.scale = scale
        self.capturedBy = capturedBy
        self.appName = appName
        self.windowTitle = windowTitle
        self.markCount = markCount
        self.targetCount = targetCount
        self.url = url
    }

    public var byAgent: Bool { capturedBy == .agent }

    /// Size in points, as a person thinks of the selection.
    public var pointSize: (width: Int, height: Int) {
        let scale = scale > 0 ? scale : 1
        return (Int((Double(size.width) / scale).rounded()), Int((Double(size.height) / scale).rounded()))
    }
}

/// The few fields of `document.json` history needs. Marks and targets are counted, not decoded, so listing
/// stays cheap and a mark kind this version does not know never hides a capture from the list.
struct HistoryHeader: Decodable {
    var formatVersion: Int
    var id: UUID
    var createdAt: Date
    var size: PixelSize
    var scale: Double
    var source: CaptureSource?
    var marks: [Skipped]
    var targets: [Skipped]

    struct Skipped: Decodable {
        init(from decoder: Decoder) throws {}
    }

    func item(url: URL) -> HistoryItem {
        HistoryItem(id: id, createdAt: createdAt, size: size, scale: scale,
                    capturedBy: source?.capturedBy ?? .person, appName: source?.appName,
                    windowTitle: source?.windowTitle, markCount: marks.count, targetCount: targets.count, url: url)
    }
}
