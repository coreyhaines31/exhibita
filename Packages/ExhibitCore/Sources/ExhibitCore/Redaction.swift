/// Fills blur regions without reading any original pixel inside them.
///
/// The invariant: output pixels inside a blur region depend only on pixels outside every blur region and on
/// the region's geometry. So two images that differ only under a blur render to identical bytes.
enum Redaction {
    static func fill(_ buffer: PixelBuffer, rects: [PixelRect], unit: Double) {
        for rect in rects {
            guard let area = PixelArea(rect, width: buffer.width, height: buffer.height) else { continue }
            for y in area.minY..<area.maxY {
                for x in area.minX..<area.maxX {
                    let offset = buffer.offset(x: x, y: y)
                    buffer.bytes[offset] = 200
                    buffer.bytes[offset + 1] = 200
                    buffer.bytes[offset + 2] = 200
                    buffer.bytes[offset + 3] = 255
                }
            }
        }
    }
}

/// A blur rectangle widened to whole pixels (so a partly covered pixel is covered) and clipped to the image.
struct PixelArea: Equatable {
    let minX: Int
    let minY: Int
    let maxX: Int
    let maxY: Int

    init?(_ rect: PixelRect, width: Int, height: Int) {
        // A blur must never be skipped for bad numbers: NaN anywhere covers the whole image, and infinities
        // clamp to the edges. Clamping happens in floating point so huge values never overflow Int.
        guard ![rect.x, rect.y, rect.x + rect.width, rect.y + rect.height].contains(where: \.isNaN) else {
            minX = 0
            minY = 0
            maxX = width
            maxY = height
            guard width > 0, height > 0 else { return nil }
            return
        }
        let standard = rect.standardized
        func clamp(_ value: Double, _ limit: Int) -> Int { Int(min(Double(limit), max(0, value))) }
        minX = clamp(standard.minX.rounded(.down), width)
        minY = clamp(standard.minY.rounded(.down), height)
        maxX = clamp(standard.maxX.rounded(.up), width)
        maxY = clamp(standard.maxY.rounded(.up), height)
        guard maxX > minX, maxY > minY else { return nil }
    }

    var width: Int { maxX - minX }
    var height: Int { maxY - minY }

    func contains(x: Int, y: Int) -> Bool { x >= minX && x < maxX && y >= minY && y < maxY }
}
