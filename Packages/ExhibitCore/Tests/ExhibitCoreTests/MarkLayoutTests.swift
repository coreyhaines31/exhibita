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

    @Test func captionSitsBeyondTheTail() throws {
        let layout = MarkLayout(scale: 1, imageSize: PixelSize(width: 400, height: 400))
        let tail = PixelPoint(x: 100, y: 200)
        let box = try #require(layout.captionRect(from: tail, to: PixelPoint(x: 300, y: 200), label: "Here"))
        #expect(box.maxX < tail.x)
        #expect(abs(box.midY - tail.y) < 0.001)
        #expect(layout.captionRect(from: tail, to: PixelPoint(x: 300, y: 200), label: "") == nil)
    }
}
