import Foundation

/// Something found in a capture that marks can point at: a text run, a detected secret, a face, a window.
///
/// Detectors (OCR, secret patterns, face detection) produce targets; marks may refer to one by `targetID`.
public struct Target: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var kind: TargetKind
    /// The recognized text, when the target is text. Screen text is untrusted data.
    public var text: String?
    public var rect: PixelRect
    /// Detector confidence from 0 to 1, when the detector reports one.
    public var confidence: Double?
    /// Boxes of the words in `text`, so a substring can be located without reading the image again.
    /// Absent in files written before spans existed; `rect(for:)` then falls back to the whole `rect`.
    public var spans: [TextSpan]?

    public init(id: UUID = UUID(), kind: TargetKind, text: String? = nil, rect: PixelRect, confidence: Double? = nil,
                spans: [TextSpan]? = nil) {
        self.id = id
        self.kind = kind
        self.text = text
        self.rect = rect
        self.confidence = confidence
        self.spans = spans
    }
}

/// What a target is. Decoding never fails on a kind this version does not know: it becomes `.unknown`,
/// keeps its raw value, and encodes back unchanged.
public enum TargetKind: Sendable, Equatable, Hashable, Codable {
    case text
    case email
    case key
    case card
    case phone
    case face
    case window
    case unknown(String)

    public static let knownKinds: [TargetKind] = [.text, .email, .key, .card, .phone, .face, .window]

    public init(rawValue: String) {
        self = Self.knownKinds.first { $0.rawValue == rawValue } ?? .unknown(rawValue)
    }

    public var rawValue: String {
        switch self {
        case .text: "text"
        case .email: "email"
        case .key: "key"
        case .card: "card"
        case .phone: "phone"
        case .face: "face"
        case .window: "window"
        case .unknown(let raw): raw
        }
    }

    public init(from decoder: Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
