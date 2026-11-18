import CoreGraphics
@testable import ExhibitCore
import ExhibitFixtures
import Testing

@Suite struct ClutterTests {
    @Test func flatBackgroundIsFreeAndEdgesAreBusy() throws {
        let image = makeImage(width: 200, height: 100) { context in
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 200, height: 100))
            context.setFillColor(CGColor(gray: 0.6, alpha: 1))
            context.fill(CGRect(x: 100, y: 40, width: 80, height: 20))
        }
        let clutter = try #require(Clutter(image: image, cell: 4))
        #expect(!clutter.isBusy(CGRect(x: 10, y: 10, width: 60, height: 30)))
        #expect(clutter.isBusy(CGRect(x: 90, y: 30, width: 40, height: 40)))
        #expect(!clutter.isBusy(from: CGPoint(x: 10, y: 80), to: CGPoint(x: 190, y: 80)))
        #expect(clutter.isBusy(from: CGPoint(x: 140, y: 10), to: CGPoint(x: 140, y: 90)))
    }
}
