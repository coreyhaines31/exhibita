import CoreGraphics
import ExhibitCore
import Foundation

/// A display as the overlay sees it: its frame in global Cocoa points (origin at the bottom-left of the main
/// display, y up) and its backing scale.
public struct DisplayGeometry: Equatable, Sendable {
    public var id: UInt32
    public var frame: CGRect
    public var scale: Double

    public init(id: UInt32, frame: CGRect, scale: Double) {
        self.id = id
        self.frame = frame
        self.scale = scale
    }
}

/// What to ask ScreenCaptureKit for: a rectangle of one display in that display's points, origin top-left
/// (`SCStreamConfiguration.sourceRect`), and the pixel size of the image to return.
public struct CaptureRegion: Equatable, Sendable {
    public var displayID: UInt32
    public var sourceRect: CGRect
    public var pixelSize: PixelSize
    public var scale: Double

    public init(displayID: UInt32, sourceRect: CGRect, pixelSize: PixelSize, scale: Double) {
        self.displayID = displayID
        self.sourceRect = sourceRect
        self.pixelSize = pixelSize
        self.scale = scale
    }
}

/// Selection geometry, from a drag in global points to the pixels to capture. A selection stays on the
/// display where the drag started, as macOS's own screenshot tool does.
public enum SelectionGeometry {
    /// A drag smaller than this, in points, on either side is a click, not a selection.
    public static let minimumSide: CGFloat = 4

    /// The rectangle between two drag points.
    public static func rect(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y))
    }

    /// The display under `point`. Edges belong to the display on their right and above, as with screen frames.
    public static func display(containing point: CGPoint, in displays: [DisplayGeometry]) -> DisplayGeometry? {
        displays.first { display in
            point.x >= display.frame.minX && point.x < display.frame.maxX
                && point.y >= display.frame.minY && point.y < display.frame.maxY
        }
    }

    /// The region for a selection (global Cocoa points) on `display`. The selection is clipped to the display
    /// and grown outward to whole pixels, so a Retina capture never splits a pixel. Nil for a click.
    public static func region(for selection: CGRect, on display: DisplayGeometry) -> CaptureRegion? {
        let clipped = selection.standardized.intersection(display.frame)
        guard !clipped.isNull, clipped.width >= minimumSide, clipped.height >= minimumSide else { return nil }
        // Display-local, top-left origin.
        let local = CGRect(x: clipped.minX - display.frame.minX, y: display.frame.maxY - clipped.maxY,
                           width: clipped.width, height: clipped.height)
        return pixelAligned(local, on: display)
    }

    /// A region given in the display's own points, top-left origin (`exhibit capture --region`), clipped to the
    /// display and grown outward to whole pixels. Nil when nothing of it is on the display.
    public static func region(local: CGRect, on display: DisplayGeometry) -> CaptureRegion? {
        let bounds = CGRect(origin: .zero, size: display.frame.size)
        let clipped = local.standardized.intersection(bounds)
        guard !clipped.isNull, clipped.width > 0, clipped.height > 0 else { return nil }
        return pixelAligned(clipped, on: display)
    }

    /// The whole display.
    public static func fullScreen(_ display: DisplayGeometry) -> CaptureRegion {
        let local = CGRect(origin: .zero, size: display.frame.size)
        // A display's own frame is always a whole number of pixels.
        return pixelAligned(local, on: display) ?? CaptureRegion(
            displayID: display.id, sourceRect: local, pixelSize: PixelSize(width: 0, height: 0), scale: display.scale
        )
    }

    /// A window's frame (Core Graphics global points, as window lists give it) as a region of the display it
    /// covers most. The parts on other displays are left out, as a drag that crosses displays is clipped.
    public static func region(forWindow frame: CGRect, in displays: [DisplayGeometry],
                              mainDisplayHeight: CGFloat) -> CaptureRegion? {
        let cocoa = cocoaRect(fromCoreGraphics: frame, mainDisplayHeight: mainDisplayHeight)
        func covered(_ display: DisplayGeometry) -> CGFloat {
            let overlap = cocoa.intersection(display.frame)
            return overlap.isNull ? 0 : overlap.width * overlap.height
        }
        guard let display = displays.max(by: { covered($0) < covered($1) }), covered(display) > 0 else { return nil }
        return region(for: cocoa, on: display)
    }

    /// The pixels of a still of the whole display that `region` covers, top-left origin. The pixels per point
    /// are measured from the still itself rather than assumed from the scale, then the rectangle is grown outward
    /// to whole pixels and clipped to the still. Nil when nothing of it is in the still.
    public static func stillPixels(of region: CaptureRegion, on display: DisplayGeometry,
                                   stillSize: PixelSize) -> PixelRect? {
        guard display.frame.width > 0, display.frame.height > 0, stillSize.width > 0, stillSize.height > 0 else {
            return nil
        }
        let scaleX = Double(stillSize.width) / display.frame.width
        let scaleY = Double(stillSize.height) / display.frame.height
        let epsilon = 1e-6
        let source = region.sourceRect.standardized
        let minX = max(0, Int((source.minX * scaleX + epsilon).rounded(.down)))
        let minY = max(0, Int((source.minY * scaleY + epsilon).rounded(.down)))
        let maxX = min(stillSize.width, Int((source.maxX * scaleX - epsilon).rounded(.up)))
        let maxY = min(stillSize.height, Int((source.maxY * scaleY - epsilon).rounded(.up)))
        guard maxX > minX, maxY > minY else { return nil }
        return PixelRect(x: Double(minX), y: Double(minY), width: Double(maxX - minX), height: Double(maxY - minY))
    }

    /// Converts a global Cocoa point (y up from the main display's bottom) to Core Graphics global coordinates
    /// (y down from the main display's top), which window lists use.
    public static func coreGraphicsPoint(fromCocoa point: CGPoint, mainDisplayHeight: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: mainDisplayHeight - point.y)
    }

    /// Converts a rectangle in Core Graphics global coordinates to global Cocoa points.
    public static func cocoaRect(fromCoreGraphics rect: CGRect, mainDisplayHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: mainDisplayHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    private static func pixelAligned(_ local: CGRect, on display: DisplayGeometry) -> CaptureRegion? {
        let scale = display.scale > 0 ? display.scale : 1
        let maxWidth = Int((display.frame.width * scale).rounded())
        let maxHeight = Int((display.frame.height * scale).rounded())
        // Snap outward, with a small tolerance so values like 99.99999 from point maths don't add a pixel.
        let epsilon = 1e-6
        let minX = max(0, Int((local.minX * scale + epsilon).rounded(.down)))
        let minY = max(0, Int((local.minY * scale + epsilon).rounded(.down)))
        let maxX = min(maxWidth, Int((local.maxX * scale - epsilon).rounded(.up)))
        let maxY = min(maxHeight, Int((local.maxY * scale - epsilon).rounded(.up)))
        guard maxX > minX, maxY > minY else { return nil }
        let source = CGRect(x: Double(minX) / scale, y: Double(minY) / scale,
                            width: Double(maxX - minX) / scale, height: Double(maxY - minY) / scale)
        return CaptureRegion(displayID: display.id, sourceRect: source,
                             pixelSize: PixelSize(width: maxX - minX, height: maxY - minY), scale: scale)
    }
}
