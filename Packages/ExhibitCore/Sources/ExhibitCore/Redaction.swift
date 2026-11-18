/// Fills blur regions with a frosted patch built without reading any original pixel inside them.
///
/// The invariant: output pixels inside a blur region depend only on pixels outside every blur region and on the
/// region's geometry. So two images that differ only under a blur render to identical bytes, and nothing under
/// a blur can be recovered from the output.
///
/// How a patch is made:
/// 1. Sample a ring a few pixels wide around the region, skipping any pixel inside any blur region.
/// 2. Average the ring per column (top and bottom edges) and per row (left and right edges), fill gaps, and smooth.
/// 3. Blend the four edges across the region (a Coons patch), so it continues the surrounding colours.
/// 4. Pull toward the ring's mean colour, lighten slightly, and add grain seeded only by the region's geometry.
enum Redaction {
    static let frost = 0.3
    static let lighten = 0.18
    static let grain = 0.03

    static func fill(_ buffer: PixelBuffer, rects: [PixelRect], unit: Double) {
        let areas = rects.compactMap { PixelArea($0, width: buffer.width, height: buffer.height) }
        guard !areas.isEmpty else { return }
        let ringWidth = max(3, Int((6 * unit).rounded()))
        let mask = BlurMask(areas, width: buffer.width, height: buffer.height)
        // Sample every ring before writing any patch, so one patch never feeds another's ring.
        let patches = areas.map { area in
            Patch(area: area, edges: EdgeProfiles(buffer: buffer, area: area, ringWidth: ringWidth, mask: mask))
        }
        let grainCell = max(1, Int(unit.rounded()))
        for patch in patches {
            patch.write(into: buffer, grainCell: grainCell)
        }
    }
}

/// Premultiplied RGBA, components from 0 to 1.
typealias Color4 = SIMD4<Double>

/// Which pixels are under any blur region.
struct BlurMask {
    private let bits: [Bool]
    private let width: Int

    init(_ areas: [PixelArea], width: Int, height: Int) {
        var bits = [Bool](repeating: false, count: width * height)
        for area in areas {
            for y in area.minY..<area.maxY {
                for x in area.minX..<area.maxX {
                    bits[y * width + x] = true
                }
            }
        }
        self.bits = bits
        self.width = width
    }

    func contains(x: Int, y: Int) -> Bool { bits[y * width + x] }
}

/// The ring around a blur region, reduced to one colour per column (top, bottom) and per row (left, right).
struct EdgeProfiles {
    var top: [Color4]
    var bottom: [Color4]
    var left: [Color4]
    var right: [Color4]
    /// The mean of every sampled ring pixel.
    var mean: Color4

    /// Used when the ring has no pixels at all (the blur covers the whole image).
    static let fallback = Color4(0.9, 0.9, 0.9, 1)

    init(buffer: PixelBuffer, area: PixelArea, ringWidth: Int, mask: BlurMask) {
        var total = Color4.zero
        var sampleTotal = 0.0

        func average(columns: Range<Int>, rows: Range<Int>) -> Color4? {
            var sum = Color4.zero
            var samples = 0.0
            for y in rows.clamped(to: 0..<buffer.height) {
                for x in columns.clamped(to: 0..<buffer.width) where !mask.contains(x: x, y: y) {
                    let offset = buffer.offset(x: x, y: y)
                    sum += Color4(Double(buffer.bytes[offset]), Double(buffer.bytes[offset + 1]),
                                  Double(buffer.bytes[offset + 2]), Double(buffer.bytes[offset + 3])) / 255
                    samples += 1
                }
            }
            total += sum
            sampleTotal += samples
            return samples > 0 ? sum / samples : nil
        }

        let above = (area.minY - ringWidth)..<area.minY
        let below = area.maxY..<(area.maxY + ringWidth)
        let before = (area.minX - ringWidth)..<area.minX
        let after = area.maxX..<(area.maxX + ringWidth)
        let rawTop = (area.minX..<area.maxX).map { average(columns: $0..<($0 + 1), rows: above) }
        let rawBottom = (area.minX..<area.maxX).map { average(columns: $0..<($0 + 1), rows: below) }
        let rawLeft = (area.minY..<area.maxY).map { average(columns: before, rows: $0..<($0 + 1)) }
        let rawRight = (area.minY..<area.maxY).map { average(columns: after, rows: $0..<($0 + 1)) }

        let mean = sampleTotal > 0 ? total / sampleTotal : Self.fallback
        self.mean = mean
        top = Self.complete(rawTop, mean: mean)
        bottom = Self.complete(rawBottom, mean: mean)
        left = Self.complete(rawLeft, mean: mean)
        right = Self.complete(rawRight, mean: mean)
    }

    /// Fills gaps from the nearest sampled neighbour (or the mean if the edge has none), then smooths.
    static func complete(_ raw: [Color4?], mean: Color4) -> [Color4] {
        guard raw.contains(where: { $0 != nil }) else { return Array(repeating: mean, count: raw.count) }
        var values = raw
        var last: Color4?
        for index in values.indices {
            if let value = values[index] { last = value } else { values[index] = last }
        }
        last = nil
        for index in values.indices.reversed() {
            if let value = values[index] { last = value } else { values[index] = last }
        }
        var smooth = values.map { $0 ?? mean }
        let radius = max(2, smooth.count / 5)
        for _ in 0..<3 {
            smooth = boxBlur(smooth, radius: radius)
        }
        return smooth
    }

    static func boxBlur(_ values: [Color4], radius: Int) -> [Color4] {
        guard values.count > 1 else { return values }
        let last = values.count - 1
        return values.indices.map { index in
            var sum = Color4.zero
            for offset in -radius...radius {
                sum += values[min(last, max(0, index + offset))]
            }
            return sum / Double(radius * 2 + 1)
        }
    }
}

/// The colours written into one blur region.
struct Patch {
    let area: PixelArea
    let edges: EdgeProfiles

    func write(into buffer: PixelBuffer, grainCell: Int) {
        let width = Double(area.width)
        let height = Double(area.height)
        let topLeft = (edges.top[0] + edges.left[0]) / 2
        let topRight = (edges.top[area.width - 1] + edges.right[0]) / 2
        let bottomLeft = (edges.bottom[0] + edges.left[area.height - 1]) / 2
        let bottomRight = (edges.bottom[area.width - 1] + edges.right[area.height - 1]) / 2
        let seed = Self.seed(for: area)

        for row in 0..<area.height {
            let v = (Double(row) + 0.5) / height
            for column in 0..<area.width {
                let u = (Double(column) + 0.5) / width
                let vertical: Color4 = (1 - v) * edges.top[column] + v * edges.bottom[column]
                let horizontal: Color4 = (1 - u) * edges.left[row] + u * edges.right[row]
                let upper: Color4 = (1 - u) * topLeft + u * topRight
                let lower: Color4 = (1 - u) * bottomLeft + u * bottomRight
                let corners: Color4 = (1 - v) * upper + v * lower
                let coons: Color4 = vertical + horizontal - corners
                let color: Color4 = coons * (1 - Redaction.frost) + edges.mean * Redaction.frost

                let alpha = min(1, max(0, color.w))
                var rgb = SIMD3(color.x, color.y, color.z)
                rgb += (SIMD3(repeating: alpha) - rgb) * Redaction.lighten
                let noise = Self.noise(seed: seed, x: column / grainCell, y: row / grainCell)
                rgb += SIMD3(repeating: noise * Redaction.grain * alpha)

                let offset = buffer.offset(x: area.minX + column, y: area.minY + row)
                buffer.bytes[offset] = Self.byte(rgb.x, limit: alpha)
                buffer.bytes[offset + 1] = Self.byte(rgb.y, limit: alpha)
                buffer.bytes[offset + 2] = Self.byte(rgb.z, limit: alpha)
                buffer.bytes[offset + 3] = Self.byte(alpha, limit: 1)
            }
        }
    }

    static func byte(_ value: Double, limit: Double) -> UInt8 {
        UInt8((min(limit, max(0, value)) * 255).rounded())
    }

    static func seed(for area: PixelArea) -> UInt64 {
        [area.minX, area.minY, area.maxX, area.maxY].reduce(0x5EED_E8B1_7A00_0001) { hash, value in
            mix(hash ^ UInt64(truncatingIfNeeded: value))
        }
    }

    /// Deterministic noise in -1...1 for a grain cell.
    static func noise(seed: UInt64, x: Int, y: Int) -> Double {
        let hash = mix(seed ^ UInt64(truncatingIfNeeded: x) &* 0x9E37_79B9_7F4A_7C15
                       ^ UInt64(truncatingIfNeeded: y) &* 0xC2B2_AE3D_27D4_EB4F)
        return Double(hash >> 40) / Double(1 << 23) - 1
    }

    /// SplitMix64's finalizer.
    static func mix(_ value: UInt64) -> UInt64 {
        var mixed = value &+ 0x9E37_79B9_7F4A_7C15
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return mixed ^ (mixed >> 31)
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
}
