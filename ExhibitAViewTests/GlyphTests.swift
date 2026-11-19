import AppKit
import XCTest

/// The menu bar glyph drawn offscreen into a bitmap: a template image with ink on the tag and clear in its cut-outs.
@MainActor
final class GlyphTests: XCTestCase {
    func testDrawsTheEvidenceTagAsATemplate() throws {
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
        XCTAssertGreaterThan(alpha(4, 12), 0.9, "tag body")
        XCTAssertGreaterThan(alpha(9, 1.05), 0.5, "string loop")
        XCTAssertLessThan(alpha(9, 7.25), 0.1, "eyelet")
        XCTAssertLessThan(alpha(9, 10.2), 0.1, "the A's apex")
        XCTAssertGreaterThan(alpha(9, 12.9), 0.9, "the A's counter")
        XCTAssertLessThan(alpha(1, 12), 0.1, "outside the tag")
    }
}
