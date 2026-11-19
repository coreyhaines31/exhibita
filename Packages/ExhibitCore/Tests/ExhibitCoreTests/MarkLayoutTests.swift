import CoreGraphics
@testable import ExhibitCore
import Foundation
import Testing

@Suite struct MarkLayoutTests {
    @Test func unitFollowsScaleOrImageSize() {
        #expect(MarkLayout(scale: 2, imageSize: PixelSize(width: 100, height: 100)).unit == 2)
        #expect(MarkLayout(scale: nil, imageSize: PixelSize(width: 800, height: 600)).unit == 1)
        #expect(MarkLayout(scale: nil, imageSize: PixelSize(width: 3200, height: 2000)).unit == 2)
    }

    @Test func labelsGrowWithTextAndScale() {
        let small = MarkLayout(scale: 1, imageSize: PixelSize(width: 100, height: 100))
        let large = MarkLayout(scale: 2, imageSize: PixelSize(width: 100, height: 100))
        #expect(small.labelSize("Click here").width > small.labelSize("Hi").width)
        #expect(abs(large.labelSize("Click here").height - 2 * small.labelSize("Click here").height) < 1)
    }

    @Test func inkBoxHoldsTheStrokes() {
        let layout = MarkLayout(scale: 2, imageSize: PixelSize(width: 400, height: 400))
        let rect = PixelRect(x: 100, y: 100, width: 80, height: 40)
        // Box: padding 3u plus half the 3u stroke, so 4.5u = 9 pixels past the bounds.
        let box = layout.inkBox(of: Mark(kind: .box, geometry: .rect(rect)))
        #expect(box == PixelRect(x: 91, y: 91, width: 98, height: 58))
        // Circle: the ellipse through the corners, padded 6u, plus half the stroke.
        let circle = layout.inkBox(of: Mark(kind: .circle, geometry: .rect(rect)))
        #expect(abs(circle.minX - (140 - 40 * 2.0.squareRoot() - 15)) < 0.001)
        let highlight = layout.inkBox(of: Mark(kind: .highlight, geometry: .rect(rect)))
        #expect(highlight == PixelRect(x: 94, y: 96, width: 92, height: 48))
        let step = layout.inkBox(of: Mark(kind: .step, geometry: .rect(rect)))
        #expect(step == PixelRect(x: 112, y: 92, width: 56, height: 56))
        #expect(layout.inkBox(of: Mark(kind: .blur, geometry: .rect(rect))) == rect)
    }

    @Test func captionSitsBeyondTheTail() throws {
        let layout = MarkLayout(scale: 1, imageSize: PixelSize(width: 400, height: 400))
        let tail = PixelPoint(x: 100, y: 200)
        let box = try #require(layout.captionRect(from: tail, to: PixelPoint(x: 300, y: 200), label: "Here"))
        #expect(box.maxX < tail.x)
        #expect(abs(box.midY - tail.y) < 0.001)
        #expect(layout.captionRect(from: tail, to: PixelPoint(x: 300, y: 200), label: "") == nil)
    }
}
