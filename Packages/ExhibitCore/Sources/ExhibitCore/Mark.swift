import Foundation

/// One annotation on a capture. Marks are stored beside the original and only flattened into pixels on export.
public struct Mark: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var kind: MarkKind
    public var geometry: MarkGeometry
    /// The target this mark was placed on, if any. The geometry is still the source of truth for rendering.
    public var targetID: UUID?
    public var style: MarkStyle

    public init(
        id: UUID = UUID(),
        kind: MarkKind,
        geometry: MarkGeometry,
        targetID: UUID? = nil,
        style: MarkStyle = MarkStyle()
    ) {
        self.id = id
        self.kind = kind
        self.geometry = geometry
        self.targetID = targetID
        self.style = style
    }

    /// The rectangle a mark covers. An arrow's is the box spanning its two ends.
    public var bounds: PixelRect {
        switch geometry {
        case .rect(let rect):
            return rect.standardized
        case let .line(from, to):
            return PixelRect(x: min(from.x, to.x), y: min(from.y, to.y),
                             width: abs(to.x - from.x), height: abs(to.y - from.y))
        }
    }
}

/// The seven marks. Decoding an unknown kind fails on purpose: a newer kind could be a redaction,
/// and silently skipping it would leak what it was meant to hide. New kinds come with a new `formatVersion`.
public enum MarkKind: String, Codable, Sendable, CaseIterable {
    case arrow
    case circle
    case blur
    case highlight
    case text
    case box
    case step
}

/// Where a mark sits. Arrows use `.line`; every other kind uses `.rect`.
///
/// Encoded flat inside the mark: `{"rect": {...}}` or `{"from": {...}, "to": {...}}`.
public enum MarkGeometry: Sendable, Equatable {
    case rect(PixelRect)
    /// From the tail to the head of an arrow.
    case line(from: PixelPoint, to: PixelPoint)
}

extension MarkGeometry: Codable {
    private enum CodingKeys: String, CodingKey {
        case rect, from, to
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let rect = try container.decodeIfPresent(PixelRect.self, forKey: .rect) {
            self = .rect(rect)
        } else {
            self = .line(
                from: try container.decode(PixelPoint.self, forKey: .from),
                to: try container.decode(PixelPoint.self, forKey: .to)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .rect(let rect):
            try container.encode(rect, forKey: .rect)
        case let .line(from, to):
            try container.encode(from, forKey: .from)
            try container.encode(to, forKey: .to)
        }
    }
}

/// How a mark looks.
public struct MarkStyle: Codable, Sendable, Equatable {
    public var color: MarkColor
    /// Text for a text mark, or an optional caption at an arrow's tail. Other kinds ignore it.
    public var label: String?
    /// The number shown in a step mark. Other kinds ignore it.
    public var stepNumber: Int?

    public init(color: MarkColor = .red, label: String? = nil, stepNumber: Int? = nil) {
        self.color = color
        self.label = label
        self.stepNumber = stepNumber
    }
}

/// The four palette colours, chosen with keys 1 to 4 in the editor.
public enum MarkColor: String, Codable, Sendable, CaseIterable {
    case red
    case yellow
    case blue
    case green
}

extension Mark {
    public static func arrow(from: PixelPoint, to: PixelPoint, color: MarkColor = .red, label: String? = nil) -> Mark {
        Mark(kind: .arrow, geometry: .line(from: from, to: to), style: MarkStyle(color: color, label: label))
    }

    public static func circle(_ rect: PixelRect, color: MarkColor = .red, targetID: UUID? = nil) -> Mark {
        Mark(kind: .circle, geometry: .rect(rect), targetID: targetID, style: MarkStyle(color: color))
    }

    public static func blur(_ rect: PixelRect, targetID: UUID? = nil) -> Mark {
        Mark(kind: .blur, geometry: .rect(rect), targetID: targetID)
    }

    public static func highlight(_ rect: PixelRect, color: MarkColor = .yellow, targetID: UUID? = nil) -> Mark {
        Mark(kind: .highlight, geometry: .rect(rect), targetID: targetID, style: MarkStyle(color: color))
    }

    /// A text label whose top-left corner sits at `at`.
    public static func text(_ label: String, at: PixelPoint, color: MarkColor = .red) -> Mark {
        Mark(kind: .text, geometry: .rect(PixelRect(x: at.x, y: at.y, width: 0, height: 0)),
             style: MarkStyle(color: color, label: label))
    }

    public static func box(_ rect: PixelRect, color: MarkColor = .red, targetID: UUID? = nil) -> Mark {
        Mark(kind: .box, geometry: .rect(rect), targetID: targetID, style: MarkStyle(color: color))
    }

    /// A numbered disc centred on `at`.
    public static func step(_ number: Int, at: PixelPoint, color: MarkColor = .red) -> Mark {
        Mark(kind: .step, geometry: .rect(PixelRect(x: at.x, y: at.y, width: 0, height: 0)),
             style: MarkStyle(color: color, stepNumber: number))
    }
}
