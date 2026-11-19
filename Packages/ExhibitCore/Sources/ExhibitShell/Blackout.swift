import CoreGraphics
import CoreText
import ExhibitCore
import Foundation

/// Never-capture windows inside a region or screen capture. ScreenCaptureKit leaves their windows out of the
/// image; these are the visible areas they covered, drawn black with a label saying why, so nothing that was
/// behind them shows through either. Where another window was in front of one, that window shows as it was.
public enum Blackout {
    public struct Region: Equatable, Sendable {
        public var rect: PixelRect
        public var reason: String

        public init(rect: PixelRect, reason: String) {
            self.rect = rect
            self.reason = reason
        }
    }

    /// The visible parts of the never-capture windows among `windows`, as pixel regions of a capture of
    /// `captureRect`.
    ///
    /// `windows` are every window on screen, front to back, and `captureRect` is in the same global top-left point
    /// space (ScreenCaptureKit's window and display frames). ScreenCaptureKit already leaves a never-capture app's
    /// pixels out of the image; the black marks where its windows were. So each listed window is blacked out only
    /// where no window in front of it covers it (`covers`): what such a window shows is its own content, never the
    /// listed app's. A listed window whose place in the order is unknown goes last, so nothing covers it. A window
    /// with nothing visible gives no region. Rects are grown outward to whole pixels and clipped to the image;
    /// parts outside the capture are dropped. `notInImage` names the apps left out of this image (Exhibit A in an
    /// agent's capture): their windows cover nothing.
    public static func regions(windows: [WindowCandidate], policy: CapturePolicy, captureRect: CGRect,
                               pixelSize: PixelSize, notInImage: Set<Int32> = []) -> [Region] {
        guard captureRect.width > 0, captureRect.height > 0, pixelSize.width > 0, pixelSize.height > 0 else {
            return []
        }
        let scaleX = Double(pixelSize.width) / captureRect.width
        let scaleY = Double(pixelSize.height) / captureRect.height
        let image = CGRect(x: 0, y: 0, width: pixelSize.width, height: pixelSize.height)
        var regions: [Region] = []
        for (index, window) in windows.enumerated() {
            guard case .blackOut(let reason) = policy.decision(for: subject(of: window)) else { continue }
            let infront = windows[..<index].filter { covers($0, policy: policy, notInImage: notInImage) }.map(\.frame)
            for part in visibleParts(of: window.frame, minus: infront) {
                let local = CGRect(x: (part.minX - captureRect.minX) * scaleX, y: (part.minY - captureRect.minY) * scaleY,
                                   width: part.width * scaleX, height: part.height * scaleY)
                let clipped = local.integral.intersection(image)
                guard !clipped.isNull, clipped.width > 0, clipped.height > 0 else { continue }
                regions.append(Region(rect: PixelRect(x: clipped.minX, y: clipped.minY, width: clipped.width,
                                                      height: clipped.height), reason: reason))
            }
        }
        return regions
    }

    /// Whether `window` hides what is behind it in the image, so a never-capture window under it needs no black
    /// there. Only an ordinary window counts: layer 0 (not a menu, popover, panel, overlay or shadow layer), fully
    /// opaque to the window server, shared with screen capture, and in the image (not a never-capture app's, not
    /// one of `notInImage`). Anything else may let the area behind it show, so the black stays.
    public static func covers(_ window: WindowCandidate, policy: CapturePolicy, notInImage: Set<Int32> = []) -> Bool {
        window.layer == 0 && window.alpha >= 1 && window.isShared && !notInImage.contains(window.ownerPID)
            && policy.entry(for: subject(of: window)) == nil
    }

    /// `frame` minus every rect in `covers`, as non-overlapping rects. Empty when nothing is left.
    public static func visibleParts(of frame: CGRect, minus covers: [CGRect]) -> [CGRect] {
        var parts = [frame.standardized]
        for cover in covers {
            parts = parts.flatMap { subtract(cover.standardized, from: $0) }
            if parts.isEmpty { break }
        }
        return parts
    }

    /// Each reason once, in the order the regions give them: one per never-capture app shown, not per piece.
    public static func reasons(_ regions: [Region]) -> [String] {
        var seen = Set<String>()
        return regions.map(\.reason).filter { seen.insert($0).inserted }
    }

    private static func subject(of window: WindowCandidate) -> CaptureSubject {
        CaptureSubject(bundleIdentifier: window.bundleIdentifier, appName: window.ownerName)
    }

    /// `rect` minus `cover`: the bands above and below the overlap at full width, then left and right of it.
    private static func subtract(_ cover: CGRect, from rect: CGRect) -> [CGRect] {
        let overlap = rect.intersection(cover)
        guard !overlap.isNull, overlap.width > 0, overlap.height > 0 else { return [rect] }
        var pieces: [CGRect] = []
        if overlap.minY > rect.minY {
            pieces.append(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: overlap.minY - rect.minY))
        }
        if overlap.maxY < rect.maxY {
            pieces.append(CGRect(x: rect.minX, y: overlap.maxY, width: rect.width, height: rect.maxY - overlap.maxY))
        }
        if overlap.minX > rect.minX {
            pieces.append(CGRect(x: rect.minX, y: overlap.minY, width: overlap.minX - rect.minX, height: overlap.height))
        }
        if overlap.maxX < rect.maxX {
            pieces.append(CGRect(x: overlap.maxX, y: overlap.minY, width: rect.maxX - overlap.maxX, height: overlap.height))
        }
        return pieces
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
                                      space: RenderColorSpace.of(image) ?? CGColorSpaceCreateDeviceRGB(),
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
