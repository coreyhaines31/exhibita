import CoreGraphics
import Foundation

/// A coarse luminance map of the image, so placement can tell plain background from busy pixels that no target
/// covers: a blur baked into a chained file, icons, photos, borders.
struct Clutter {
    /// Pixels per cell side.
    let cell: Double
    let columns: Int
    let rows: Int
    /// One luminance byte per cell, top row first.
    let luma: [UInt8]

    /// Spread of luminance above which an area counts as busy. Flat backgrounds measure about 0.
    static let busyDeviation = 6.0

    init?(image: CGImage, cell: Double) {
        let columns = max(1, Int((Double(image.width) / cell).rounded(.up)))
        let rows = max(1, Int((Double(image.height) / cell).rounded(.up)))
        var luma = [UInt8](repeating: 0, count: columns * rows)
        let drawn = luma.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(data: raw.baseAddress, width: columns, height: rows, bitsPerComponent: 8,
                                          bytesPerRow: columns, space: CGColorSpaceCreateDeviceGray(),
                                          bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: columns, height: rows))
            return true
        }
        guard drawn else { return nil }
        self.cell = Double(image.width) / Double(columns)
        self.columns = columns
        self.rows = rows
        self.luma = luma
    }

    /// Whether the cells inside `rect` vary more than a flat background does.
    func isBusy(_ rect: CGRect) -> Bool {
        let minColumn = max(0, Int((rect.minX / cell).rounded(.down)))
        let maxColumn = min(columns - 1, Int((rect.maxX / cell).rounded(.up)) - 1)
        let minRow = max(0, Int((rect.minY / cell).rounded(.down)))
        let maxRow = min(rows - 1, Int((rect.maxY / cell).rounded(.up)) - 1)
        guard minColumn <= maxColumn, minRow <= maxRow else { return false }
        var values: [Double] = []
        for row in minRow...maxRow {
            for column in minColumn...maxColumn { values.append(Double(luma[row * columns + column])) }
        }
        return Self.deviation(values) > Self.busyDeviation
    }

    /// Whether the cells along a line vary more than a flat background does.
    func isBusy(from start: CGPoint, to end: CGPoint) -> Bool {
        let length = hypot(end.x - start.x, end.y - start.y)
        let steps = max(2, Int(length / cell))
        let values = (0...steps).compactMap { step -> Double? in
            let along = Double(step) / Double(steps)
            let column = Int((start.x + (end.x - start.x) * along) / cell)
            let row = Int((start.y + (end.y - start.y) * along) / cell)
            guard (0..<columns).contains(column), (0..<rows).contains(row) else { return nil }
            return Double(luma[row * columns + column])
        }
        return Self.deviation(values) > Self.busyDeviation
    }

    private static func deviation(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        return (values.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(values.count)).squareRoot()
    }
}
