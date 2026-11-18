import CoreGraphics

/// A point in pixels of the original image, origin top-left, y growing downward.
public struct PixelPoint: Codable, Sendable, Equatable, Hashable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public var cgPoint: CGPoint { CGPoint(x: x, y: y) }
}

/// A size in whole pixels.
public struct PixelSize: Codable, Sendable, Equatable, Hashable {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

/// A rectangle in pixels of the original image, origin top-left, y growing downward.
public struct PixelRect: Codable, Sendable, Equatable, Hashable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var minX: Double { min(x, x + width) }
    public var minY: Double { min(y, y + height) }
    public var maxX: Double { max(x, x + width) }
    public var maxY: Double { max(y, y + height) }
    public var midX: Double { (minX + maxX) / 2 }
    public var midY: Double { (minY + maxY) / 2 }

    /// The same rectangle with a non-negative width and height.
    public var standardized: PixelRect {
        PixelRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    public var cgRect: CGRect { CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY) }
}
