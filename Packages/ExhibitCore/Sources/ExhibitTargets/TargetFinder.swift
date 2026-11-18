import CoreGraphics
import ExhibitCore
import Foundation
import Vision

/// Finds targets in an image: one `.text` target per recognized line, `.email`, `.key`, `.card` and `.phone`
/// targets for sensitive items in that text.
///
/// Everything runs on the Mac with Vision; nothing leaves it. `findTargets(in:)` is synchronous and takes a
/// fraction of a second to a few seconds depending on image size, so call it off the main thread.
public struct TargetFinder: Sendable {
    /// What replaces each UTF-16 code unit of a sensitive match in stored text.
    public static let maskCharacter: Character = "\u{2022}"

    public init() {}

    /// Targets in pixels of `image`, origin top-left, ordered top to bottom, then left to right.
    ///
    /// Sensitive items never appear in the output as text: their targets have no `text`, and the same characters
    /// in the `.text` target of their line are replaced by `maskCharacter`, one for each UTF-16 code unit, so
    /// offsets and spans still line up.
    public func findTargets(in image: CGImage) throws -> [Target] {
        let textRequest = VNRecognizeTextRequest()
        textRequest.recognitionLevel = .accurate
        // Correction "fixes" keys, codes and names into dictionary words.
        textRequest.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([textRequest])

        let grid = InkGrid(image)
        var targets: [Target] = []
        for observation in textRequest.results ?? [] {
            guard let candidate = observation.topCandidates(1).first, !candidate.string.isEmpty else { continue }
            targets += Self.targets(forLine: candidate, observation: observation, image: image, grid: grid)
        }
        return Self.ordered(targets)
    }

    private static func targets(forLine candidate: VNRecognizedText, observation: VNRecognizedTextObservation,
                                image: CGImage, grid: InkGrid?) -> [Target] {
        let text = candidate.string
        let toPixels = { (box: CGRect) in VisionGeometry.pixelRect(box, width: image.width, height: image.height) }
        var spans: [TextSpan] = []
        for word in wordRanges(in: text) {
            guard let box = try? candidate.boundingBox(for: word)?.boundingBox, box.width > 0, box.height > 0 else {
                continue
            }
            let rect = toPixels(box)
            let range = NSRange(word, in: text)
            spans.append(TextSpan(start: range.location, length: range.length, rect: grid?.trimmed(rect) ?? rect))
        }
        let lineBox = toPixels(observation.boundingBox)
        let rect = spans.isEmpty ? (grid?.trimmed(lineBox) ?? lineBox) : union(spans.map(\.rect))
        return lineTargets(text: text, rect: rect, confidence: Double(candidate.confidence),
                           spans: spans.isEmpty ? nil : spans)
    }

    /// The line's `.text` target, with sensitive matches masked, followed by a target for each match.
    static func lineTargets(text: String, rect: PixelRect, confidence: Double?, spans: [TextSpan]?) -> [Target] {
        let matches = SensitivePatterns.matches(in: text)
        let line = Target(kind: .text, text: masked(text, ranges: matches.map(\.range)), rect: rect,
                          confidence: confidence, spans: spans)
        let sensitive = matches.map { match in
            Target(kind: match.kind, rect: line.rect(forUTF16Range: match.range) ?? rect, confidence: confidence)
        }
        return [line] + sensitive
    }

    /// `text` with every UTF-16 code unit inside `ranges` replaced by `maskCharacter`, which is one code unit.
    static func masked(_ text: String, ranges: [NSRange]) -> String {
        guard !ranges.isEmpty else { return text }
        var units = Array(text.utf16)
        let mask = maskCharacter.utf16.first ?? 0x2022
        for range in ranges {
            let lower = max(0, range.location)
            let upper = min(units.count, range.location + range.length)
            guard lower < upper else { continue }
            for index in lower..<upper { units[index] = mask }
        }
        return String(decoding: units, as: UTF16.self)
    }

    /// Runs of non-whitespace characters.
    static func wordRanges(in text: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var start: String.Index?
        for index in text.indices {
            if text[index].isWhitespace {
                if let begin = start { ranges.append(begin..<index) }
                start = nil
            } else if start == nil {
                start = index
            }
        }
        if let begin = start { ranges.append(begin..<text.endIndex) }
        return ranges
    }

    /// Top to bottom, then left to right, then by kind, so the same image always lists targets in the same order.
    static func ordered(_ targets: [Target]) -> [Target] {
        let rank = { (kind: TargetKind) in TargetKind.knownKinds.firstIndex(of: kind) ?? TargetKind.knownKinds.count }
        return targets.sorted { lhs, rhs in
            let left = lhs.rect.standardized
            let right = rhs.rect.standardized
            return (left.minY, left.minX, rank(lhs.kind), left.maxX, left.maxY)
                < (right.minY, right.minX, rank(rhs.kind), right.maxX, right.maxY)
        }
    }

    private static func union(_ rects: [PixelRect]) -> PixelRect {
        let box = rects.map(\.cgRect).reduce(CGRect.null) { $0.union($1) }
        return PixelRect(x: box.minX, y: box.minY, width: box.width, height: box.height)
    }
}
