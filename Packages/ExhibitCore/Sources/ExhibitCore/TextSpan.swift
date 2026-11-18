import Foundation

/// A run of a text target's `text` (usually one word) and the box it covers.
///
/// Offsets count UTF-16 code units from the start of `text`, matching `NSRange` and JavaScript strings.
public struct TextSpan: Codable, Sendable, Equatable, Hashable {
    public var start: Int
    public var length: Int
    public var rect: PixelRect

    public init(start: Int, length: Int, rect: PixelRect) {
        self.start = start
        self.length = length
        self.rect = rect
    }

    public var end: Int { start + length }
}

extension Target {
    /// The box covering `range` of `text`, built from the spans it touches.
    ///
    /// A span covered completely contributes its whole box; a partly covered span contributes a slice in
    /// proportion to the characters covered, which is an estimate for proportional fonts. Without spans the
    /// whole `rect` is treated as one span. Returns nil when there is no text, the range is empty or out of
    /// bounds, or it covers only the gaps between spans (such as a lone space).
    public func rect(forUTF16Range range: NSRange) -> PixelRect? {
        guard let text, range.location != NSNotFound, range.length > 0, range.location >= 0,
              range.location + range.length <= text.utf16.count else { return nil }
        let spans = self.spans ?? [TextSpan(start: 0, length: text.utf16.count, rect: rect)]
        let lower = range.location
        let upper = range.location + range.length
        var union: CGRect?
        for span in spans where span.length > 0 {
            let from = max(lower, span.start)
            let to = min(upper, span.end)
            guard from < to else { continue }
            let box = span.rect.standardized
            let startFraction = Double(from - span.start) / Double(span.length)
            let endFraction = Double(to - span.start) / Double(span.length)
            let slice = CGRect(x: box.x + box.width * startFraction, y: box.y,
                               width: box.width * (endFraction - startFraction), height: box.height)
            union = union.map { $0.union(slice) } ?? slice
        }
        return union.map { PixelRect(x: $0.minX, y: $0.minY, width: $0.width, height: $0.height) }
    }

    /// The box covering `range`, which must be a range of this target's `text`.
    public func rect(for range: Range<String.Index>) -> PixelRect? {
        guard let text else { return nil }
        return rect(forUTF16Range: NSRange(range, in: text))
    }
}
