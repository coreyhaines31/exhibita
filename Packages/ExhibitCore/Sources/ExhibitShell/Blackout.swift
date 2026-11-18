import CoreGraphics
import CoreText
import ExhibitCore
import Foundation

/// Never-capture windows inside a region or screen capture. ScreenCaptureKit leaves their windows out of the
/// image; these are the areas they covered, drawn black with a label saying why, so nothing that was behind them
/// shows through either.
public enum Blackout {
    public struct Region: Equatable, Sendable {
        public var rect: PixelRect
        public var reason: String

        public init(rect: PixelRect, reason: String) {
            self.rect = rect
            self.reason = reason
        }
    }

    /// The never-capture windows among `windows`, as pixel regions of a capture of `captureRect`.
    ///
    /// `windows` and `captureRect` are in the same global top-left point space (ScreenCaptureKit's window and
    /// display frames). Each window's whole frame is blacked out, even where another window covers part of it:
    /// covering too much is safe, too little is not. Rects are grown outward to whole pixels and clipped to the
    /// image; windows outside the capture are dropped.
    public static func regions(windows: [WindowCandidate], policy: CapturePolicy, captureRect: CGRect,
                               pixelSize: PixelSize) -> [Region] {
        guard captureRect.width > 0, captureRect.height > 0, pixelSize.width > 0, pixelSize.height > 0 else {
            return []
        }
        let scaleX = Double(pixelSize.width) / captureRect.width
        let scaleY = Double(pixelSize.height) / captureRect.height
        let image = CGRect(x: 0, y: 0, width: pixelSize.width, height: pixelSize.height)
        return windows.compactMap { window in
            let subject = CaptureSubject(bundleIdentifier: window.bundleIdentifier, appName: window.ownerName)
            guard case .blackOut(let reason) = policy.decision(for: subject) else { return nil }
            let local = CGRect(x: (window.frame.minX - captureRect.minX) * scaleX,
                               y: (window.frame.minY - captureRect.minY) * scaleY,
                               width: window.frame.width * scaleX, height: window.frame.height * scaleY)
            let clipped = local.integral.intersection(image)
            guard !clipped.isNull, clipped.width > 0, clipped.height > 0 else { return nil }
            return Region(rect: PixelRect(x: clipped.minX, y: clipped.minY, width: clipped.width,
                                          height: clipped.height), reason: reason)
        }
    }

    /// The label drawn on a region.
    public static func label(for reason: String) -> String {
        "Hidden by Exhibit A: \(reason)"
    }

    /// `image` with every region filled black and labelled. The label is drawn only where it fits.
    public static func paint(_ image: CGImage, regions: [Region], scale: Double) throws -> CGImage {
        guard !regions.isEmpty else { return image }
        let width = image.width
        let height = image.height
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw ExhibitError.renderFailed
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        // Flip to top-left pixels, the capture's coordinates.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        for region in regions {
            let rect = CGRect(x: region.rect.x, y: region.rect.y, width: region.rect.width, height: region.rect.height)
            context.setFillColor(CGColor(gray: 0, alpha: 1))
            context.fill(rect)
            drawLabel(label(for: region.reason), in: rect, context: context, scale: max(scale, 1))
        }
        guard let painted = context.makeImage() else { throw ExhibitError.renderFailed }
        return painted
    }

    private static func drawLabel(_ text: String, in rect: CGRect, context: CGContext, scale: Double) {
        let font = CTFontCreateUIFontForLanguage(.system, 13 * scale, nil)
            ?? CTFontCreateWithName("Helvetica" as CFString, 13 * scale, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0.85, alpha: 1)
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        let textWidth = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, nil))
        let padding = 8 * scale
        guard textWidth + 2 * padding <= rect.width, ascent + descent + 2 * padding <= rect.height else { return }
        context.saveGState()
        // CoreText draws with y up; flip back around the baseline.
        let baseline = rect.midY + (ascent - descent) / 2
        context.textMatrix = .identity
        context.translateBy(x: rect.midX - textWidth / 2, y: baseline)
        context.scaleBy(x: 1, y: -1)
        context.textPosition = .zero
        CTLineDraw(line, context)
        context.restoreGState()
    }
}
