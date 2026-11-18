import CoreGraphics
import Foundation

/// Flattens marks onto an original image. Deterministic: the same inputs give the same pixels, and
/// `PNG.encode` of the result gives the same bytes, on a given machine and OS version.
///
/// Blur marks are applied first, straight onto the original's pixels, so every other mark sits on top of them.
/// The rest are drawn in array order. The output is one flattened image with no layers and no copy of the original.
public enum Renderer {
    /// Renders `marks` over `original`.
    ///
    /// - Parameter scale: the capture's backing scale, which sets stroke widths and label sizes. When `nil`,
    ///   it is inferred from the image size, which suits plain image files with no document.
    public static func render(original: CGImage, marks: [Mark], scale: Double? = nil) throws -> CGImage {
        let width = original.width
        let height = original.height
        guard width > 0, height > 0,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw ExhibitError.renderFailed
        }
        let metrics = MarkMetrics(unit: scale ?? MarkMetrics.inferredUnit(width: width, height: height))

        context.interpolationQuality = .none
        context.draw(original, in: CGRect(x: 0, y: 0, width: width, height: height))

        // The raw rectangle, not `bounds`: standardizing could quietly turn a NaN edge into a zero-size blur.
        let blurRects = marks.filter { $0.kind == .blur }.map { mark in
            if case .rect(let rect) = mark.geometry { return rect }
            return mark.bounds
        }
        if !blurRects.isEmpty {
            guard let data = context.data else { throw ExhibitError.renderFailed }
            let buffer = data.bindMemory(to: UInt8.self, capacity: context.bytesPerRow * height)
            Redaction.fill(PixelBuffer(bytes: buffer, width: width, height: height, bytesPerRow: context.bytesPerRow),
                           rects: blurRects, unit: metrics.unit)
        }

        // Marks are drawn in top-left pixel coordinates.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.setShouldSmoothFonts(false)
        context.setAllowsFontSubpixelPositioning(false)
        context.setAllowsFontSubpixelQuantization(false)
        let painter = MarkPainter(context: context, metrics: metrics)
        for mark in marks where mark.kind != .blur {
            painter.draw(mark)
        }

        guard let image = context.makeImage() else { throw ExhibitError.renderFailed }
        return image
    }

    /// Renders a document's marks over its original, using the document's scale.
    public static func render(_ document: CaptureDocument, original: CGImage) throws -> CGImage {
        try render(original: original, marks: document.marks, scale: document.scale)
    }

    /// Renders and encodes as PNG in one step.
    public static func renderPNG(original: CGImage, marks: [Mark], scale: Double? = nil) throws -> Data {
        try PNG.encode(render(original: original, marks: marks, scale: scale))
    }
}

/// Sizes for marks, in pixels, derived from one unit: 1 on a 1x capture, 2 on a Retina capture.
struct MarkMetrics {
    let unit: Double

    init(unit: Double) {
        self.unit = max(0.5, unit)
    }

    /// A unit for images with no known scale: 1 up to about 1600 pixels on the long side, growing past that.
    static func inferredUnit(width: Int, height: Int) -> Double {
        min(4, max(1, Double(max(width, height)) / 1600))
    }

    var stroke: Double { 3 * unit }
    var arrowStroke: Double { 4 * unit }
    var arrowHeadLength: Double { 18 * unit }
    var arrowHeadHalfWidth: Double { 10 * unit }
    var circlePadding: Double { 6 * unit }
    var boxPadding: Double { 3 * unit }
    var boxCornerRadius: Double { 5 * unit }
    var highlightPadding: CGSize { CGSize(width: 3 * unit, height: 2 * unit) }
    var highlightCornerRadius: Double { 3 * unit }
    var labelFontSize: Double { 15 * unit }
    var labelPadding: CGSize { CGSize(width: 8 * unit, height: 5 * unit) }
    var labelCornerRadius: Double { 6 * unit }
    var labelGap: Double { 4 * unit }
    var stepDiameter: Double { 28 * unit }
    var stepRing: Double { 2 * unit }
    var stepFontSize: Double { 15 * unit }
    var shadowOffset: Double { 1.5 * unit }
    var shadowBlur: Double { 4 * unit }
    var redactionRing: Int { max(3, Int((6 * unit).rounded())) }
}

/// A view of 8-bit RGBA premultiplied pixels, top row first.
struct PixelBuffer {
    let bytes: UnsafeMutablePointer<UInt8>
    let width: Int
    let height: Int
    let bytesPerRow: Int

    func offset(x: Int, y: Int) -> Int { y * bytesPerRow + x * 4 }
}

extension MarkColor {
    /// The stroke and fill colour, sRGB.
    var rgb: RGB {
        switch self {
        case .red: RGB(1.0, 0.231, 0.188)
        case .yellow: RGB(1.0, 0.8, 0.0)
        case .blue: RGB(0.039, 0.518, 1.0)
        case .green: RGB(0.204, 0.78, 0.349)
        }
    }

    /// A light marker tone, multiplied over the image so dark text stays dark.
    var markerRGB: RGB {
        switch self {
        case .red: RGB(1.0, 0.72, 0.70)
        case .yellow: RGB(1.0, 0.90, 0.36)
        case .blue: RGB(0.66, 0.83, 1.0)
        case .green: RGB(0.71, 0.94, 0.76)
        }
    }

    /// Text drawn on a backing of this colour.
    var onColorRGB: RGB {
        self == .yellow ? RGB(0.11, 0.11, 0.12) : RGB(1, 1, 1)
    }
}

/// An sRGB colour, components from 0 to 1.
struct RGB: Equatable {
    var r: Double
    var g: Double
    var b: Double

    init(_ r: Double, _ g: Double, _ b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }
}

func srgb(_ rgb: RGB, alpha: Double = 1) -> CGColor {
    CGColor(srgbRed: rgb.r, green: rgb.g, blue: rgb.b, alpha: alpha)
}
