@testable import ExhibitCore
import Testing

@Suite struct GeometryTests {
    @Test func standardizesNegativeSizes() {
        let rect = PixelRect(x: 50, y: 40, width: -20, height: -10)
        #expect(rect.standardized == PixelRect(x: 30, y: 30, width: 20, height: 10))
        #expect(rect.midX == 40)
        #expect(rect.midY == 35)
    }
}
