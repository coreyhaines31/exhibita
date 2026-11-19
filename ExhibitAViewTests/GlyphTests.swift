import AppKit
import XCTest

/// The menu bar glyph drawn offscreen into a bitmap: a template image with ink on the window outline and the disc,
/// clear in the gap around the disc and in the A.
@MainActor
final class GlyphTests: XCTestCase {
    func testDrawsTheExhibitPlateAsATemplate() throws {
        let image = Glyph.image()
        XCTAssertTrue(image.isTemplate)
        XCTAssertEqual(image.size, NSSize(width: 18, height: 18))

        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 72, pixelsHigh: 72,
                                                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                                    isPlanar: false, colorSpaceName: .deviceRGB,
                                                    bytesPerRow: 0, bitsPerPixel: 0))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        image.draw(in: NSRect(x: 0, y: 0, width: 72, height: 72))
        NSGraphicsContext.restoreGraphicsState()

        // Points in the glyph's 18 pt space, top-left origin, sampled at 4 px per point.
        func alpha(_ x: CGFloat, _ y: CGFloat) -> CGFloat {
            bitmap.colorAt(x: Int(x * 4), y: Int(y * 4))?.alphaComponent ?? 0
        }
        XCTAssertGreaterThan(alpha(1.75, 5), 0.9, "window's left edge")
        XCTAssertGreaterThan(alpha(6, 1.75), 0.9, "window's top edge")
        XCTAssertGreaterThan(alpha(11.75, 3), 0.9, "window's right edge, clear of the disc")
        XCTAssertLessThan(alpha(6, 5), 0.1, "inside the window")
        XCTAssertLessThan(alpha(11.75, 5), 0.1, "window's right edge, cut clear around the disc")
        XCTAssertGreaterThan(alpha(11.5, 16.5), 0.9, "disc below the A")
        XCTAssertGreaterThan(alpha(6.2, 12), 0.9, "disc left of the A")
        XCTAssertLessThan(alpha(11.5, 9.2), 0.1, "the A's apex")
        XCTAssertLessThan(alpha(9.2, 14.2), 0.1, "the A's left leg")
        XCTAssertGreaterThan(alpha(11.5, 11.4), 0.9, "the A's counter")
        XCTAssertLessThan(alpha(17, 2), 0.1, "outside the glyph")
    }
}
