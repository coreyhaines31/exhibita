import CoreGraphics
@testable import ExhibitCore
import Foundation
import Testing

@Suite struct RendererTests {
    let marks: [Mark] = [
        .highlight(PixelRect(x: 20, y: 20, width: 80, height: 14)),
        .box(PixelRect(x: 10, y: 50, width: 100, height: 40), color: .blue),
        .circle(PixelRect(x: 140, y: 30, width: 50, height: 20), color: .green),
        .arrow(from: PixelPoint(x: 200, y: 140), to: PixelPoint(x: 120, y: 80), label: "Here"),
        .text("Label", at: PixelPoint(x: 20, y: 120), color: .yellow),
        .step(1, at: PixelPoint(x: 220, y: 30)),
        .blur(PixelRect(x: 150, y: 100, width: 60, height: 20))
    ]

    @Test func sameInputGivesSameBytes() throws {
        let original = solidImage(width: 240, height: 160, gray: 0.95)
        let first = try Renderer.renderPNG(original: original, marks: marks, scale: 1)
        let second = try Renderer.renderPNG(original: original, marks: marks, scale: 1)
        #expect(first == second)
    }

    @Test func keepsTheOriginalSizeAndChangesOnlyMarkedAreas() throws {
        let original = solidImage(width: 240, height: 160, gray: 0.95)
        let output = try Renderer.render(original: original, marks: marks, scale: 1)
        #expect(output.width == 240 && output.height == 160)
        let pixels = Pixels(output)
        #expect(pixels.pixel(x: 0, y: 159) == Pixels(original).pixel(x: 0, y: 159))
        // Highlight multiplies the marker tone into the light background.
        let highlighted = pixels.pixel(x: 60, y: 27)
        #expect(highlighted[0] > 200 && highlighted[2] < 120)
    }

    @Test func noMarksReturnsTheOriginalPixels() throws {
        let original = makeImage(width: 50, height: 30) { context in
            context.setFillColor(CGColor(srgbRed: 0.1, green: 0.5, blue: 0.7, alpha: 1))
            context.fill(CGRect(x: 5, y: 5, width: 20, height: 10))
        }
        #expect(Pixels(try Renderer.render(original: original, marks: [])) == Pixels(original))
    }

    @Test func strokesScaleWithTheCapture() {
        #expect(MarkMetrics(unit: 2).stroke == 2 * MarkMetrics(unit: 1).stroke)
        #expect(MarkMetrics.inferredUnit(width: 1440, height: 900) == 1)
        #expect(MarkMetrics.inferredUnit(width: 3200, height: 2000) == 2)
    }

    @Test func toleratesDegenerateGeometry() throws {
        let original = solidImage(width: 40, height: 40, gray: 0.5)
        let odd: [Mark] = [
            .arrow(from: PixelPoint(x: 10, y: 10), to: PixelPoint(x: 10, y: 10)),
            .blur(PixelRect(x: -1e300, y: 5, width: .infinity, height: 3)),
            .blur(PixelRect(x: 100, y: 100, width: 10, height: 10)),
            .box(PixelRect(x: 30, y: 30, width: -20, height: -20)),
            .text("", at: PixelPoint(x: 0, y: 0))
        ]
        _ = try Renderer.render(original: original, marks: odd)
    }
}
