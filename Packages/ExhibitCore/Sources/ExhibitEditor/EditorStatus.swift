import CoreGraphics
import ExhibitCore
import Foundation

/// The status line under the toolbar. A notice from the last action wins; then "reading text" while targets
/// load; then the quiet count of secrets nothing covers yet. It never blocks copying.
public enum EditorStatus: Equatable, Sendable {
    case none
    case readingText
    case secrets(Int)
    case notice(String)

    public var text: String? {
        switch self {
        case .none: nil
        case .readingText: "Reading text"
        case .secrets(let count): count == 1 ? "1 possible secret. ⇧B to blur." : "\(count) possible secrets. ⇧B to blur."
        case .notice(let message): message
        }
    }
}

/// A short in-progress shape while a person drags, drawn as an outline over the rendered image. Committed
/// marks are always drawn by `Renderer`; a draft is never exported.
public struct EditorDraft: Equatable, Sendable {
    public var kind: MarkKind
    public var geometry: MarkGeometry
    public var color: MarkColor
    public var label: String?
    public var stepNumber: Int?

    public init(kind: MarkKind, geometry: MarkGeometry, color: MarkColor, label: String? = nil, stepNumber: Int? = nil) {
        self.kind = kind
        self.geometry = geometry
        self.color = color
        self.label = label
        self.stepNumber = stepNumber
    }

    init(_ mark: Mark) {
        self.init(kind: mark.kind, geometry: mark.geometry, color: mark.style.color, label: mark.style.label,
                  stepNumber: mark.style.stepNumber)
    }
}

/// The result of a key press.
public enum EditorKeyResult: Equatable, Sendable {
    /// The editor did it (a tool, a colour, undo, typing into a label).
    case handled
    /// The app has to do it: copy, save, copy the path, close.
    case app(EditorCommand)
    /// Not an editor key.
    case ignored
}

/// Flattening for the clipboard and for files. Always the renderer, so redaction always applies, and always
/// `PNG.encode`, so exports carry no metadata.
public enum EditorExport {
    public static func png(_ document: CaptureDocument, original: CGImage) throws -> Data {
        try Renderer.renderPNG(original: original, marks: document.marks, scale: document.scale)
    }

    /// "Safari 2026-11-18 at 15.41.07-marked.png", following the CLI's `-marked` naming.
    public static func fileName(for document: CaptureDocument, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let app = (document.source?.appName ?? "").replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let base = (app.isEmpty ? "Capture" : app) + " " + formatter.string(from: document.createdAt)
        return base + "-marked.png"
    }

    /// Writes `png` into `directory` as `name`, atomically, and returns the file's URL.
    public static func write(_ png: Data, named name: String, in directory: URL) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try png.write(to: url, options: .atomic)
        return url
    }
}
