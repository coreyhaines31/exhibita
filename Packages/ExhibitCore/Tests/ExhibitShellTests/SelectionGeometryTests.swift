import CoreGraphics
import ExhibitCore
import ExhibitShell
import Testing

@Suite struct SelectionGeometryTests {
    /// A 1512 x 982 point Retina laptop as the main display, and a 1920 x 1080 point 1x monitor to its right,
    /// placed 200 points higher.
    let laptop = DisplayGeometry(id: 1, frame: CGRect(x: 0, y: 0, width: 1512, height: 982), scale: 2)
    let monitor = DisplayGeometry(id: 2, frame: CGRect(x: 1512, y: 200, width: 1920, height: 1080), scale: 1)

    @Test func rectFromADragInAnyDirection() {
        let rect = SelectionGeometry.rect(from: CGPoint(x: 300, y: 100), to: CGPoint(x: 100, y: 400))
        #expect(rect == CGRect(x: 100, y: 100, width: 200, height: 300))
    }

    @Test func findsTheDisplayUnderAPoint() {
        let displays = [laptop, monitor]
        #expect(SelectionGeometry.display(containing: CGPoint(x: 10, y: 10), in: displays)?.id == 1)
        #expect(SelectionGeometry.display(containing: CGPoint(x: 1512, y: 300), in: displays)?.id == 2)
        #expect(SelectionGeometry.display(containing: CGPoint(x: 1600, y: 100), in: displays) == nil)
    }

    @Test func retinaRegionFlipsToTopLeftAndDoublesPixels() throws {
        // 200 x 100 points whose bottom-left is 50 points above the laptop's bottom.
        let selection = CGRect(x: 100, y: 50, width: 200, height: 100)
        let region = try #require(SelectionGeometry.region(for: selection, on: laptop))
        #expect(region.displayID == 1)
        #expect(region.sourceRect == CGRect(x: 100, y: 982 - 150, width: 200, height: 100))
        #expect(region.pixelSize == PixelSize(width: 400, height: 200))
        #expect(region.scale == 2)
    }

    @Test func regionOnASecondDisplayIsLocalToIt() throws {
        let selection = CGRect(x: 1612, y: 1180, width: 300, height: 50)
        let region = try #require(SelectionGeometry.region(for: selection, on: monitor))
        // 100 points in from the monitor's left; its top is at 1280, so 1280 - 1230 = 50 from the top.
        #expect(region.sourceRect == CGRect(x: 100, y: 50, width: 300, height: 50))
        #expect(region.pixelSize == PixelSize(width: 300, height: 50))
    }

    @Test func agentRegionsAreDisplayLocalAndClipped() throws {
        let retina = DisplayGeometry(id: 4, frame: CGRect(x: -1440, y: 0, width: 1440, height: 900), scale: 2)
        let region = try #require(SelectionGeometry.region(local: CGRect(x: 10.25, y: 20, width: 100, height: 50),
                                                           on: retina))
        #expect(region.displayID == 4)
        #expect(region.sourceRect == CGRect(x: 10, y: 20, width: 100.5, height: 50))
        #expect(region.pixelSize == PixelSize(width: 201, height: 100))
        let clipped = try #require(SelectionGeometry.region(local: CGRect(x: 1400, y: 880, width: 100, height: 100),
                                                            on: retina))
        #expect(clipped.sourceRect == CGRect(x: 1400, y: 880, width: 40, height: 20))
        #expect(SelectionGeometry.region(local: CGRect(x: 2000, y: 0, width: 10, height: 10), on: retina) == nil)
    }

    @Test func halfPointsGrowOutwardToWholePixels() throws {
        let oneX = DisplayGeometry(id: 3, frame: CGRect(x: 0, y: 0, width: 800, height: 600), scale: 1)
        let selection = CGRect(x: 10.4, y: 20.6, width: 99.3, height: 50.2)
        let region = try #require(SelectionGeometry.region(for: selection, on: oneX))
        // x 10.4...109.7 -> 10...110; local y top = 600 - 70.8 = 529.2 -> 529, bottom = 579.4 -> 580.
        #expect(region.sourceRect == CGRect(x: 10, y: 529, width: 100, height: 51))
        #expect(region.pixelSize == PixelSize(width: 100, height: 51))

        let retina = try #require(SelectionGeometry.region(for: CGRect(x: 10.25, y: 0, width: 20, height: 20), on: laptop))
        #expect(retina.sourceRect.minX == 10)
        #expect(retina.pixelSize.width == 41)
    }

    @Test func aDragAcrossDisplaysStaysOnTheFirst() throws {
        let selection = CGRect(x: 1400, y: 300, width: 300, height: 100)
        let region = try #require(SelectionGeometry.region(for: selection, on: laptop))
        #expect(region.sourceRect.maxX == 1512)
        #expect(region.pixelSize.width == 224)
    }

    @Test func aClickIsNotASelection() {
        #expect(SelectionGeometry.region(for: CGRect(x: 10, y: 10, width: 2, height: 80), on: laptop) == nil)
        #expect(SelectionGeometry.region(for: CGRect(x: 2000, y: 10, width: 80, height: 80), on: laptop) == nil)
    }

    @Test func fullScreenCoversEveryPixel() {
        let region = SelectionGeometry.fullScreen(laptop)
        #expect(region.sourceRect == CGRect(x: 0, y: 0, width: 1512, height: 982))
        #expect(region.pixelSize == PixelSize(width: 3024, height: 1964))
        let third = DisplayGeometry(id: 4, frame: CGRect(x: -1280, y: 0, width: 1280, height: 800), scale: 3)
        #expect(SelectionGeometry.fullScreen(third).pixelSize == PixelSize(width: 3840, height: 2400))
    }

    @Test func convertsBetweenCocoaAndCoreGraphicsCoordinates() {
        let point = SelectionGeometry.coreGraphicsPoint(fromCocoa: CGPoint(x: 40, y: 900), mainDisplayHeight: 982)
        #expect(point == CGPoint(x: 40, y: 82))
        let rect = SelectionGeometry.cocoaRect(fromCoreGraphics: CGRect(x: 0, y: 0, width: 100, height: 30),
                                               mainDisplayHeight: 982)
        #expect(rect == CGRect(x: 0, y: 952, width: 100, height: 30))
    }
}

@Suite struct WindowPickerTests {
    let windows = [
        WindowCandidate(id: 9, frame: CGRect(x: 1400, y: 0, width: 24, height: 24), layer: 25, ownerPID: 5),
        WindowCandidate(id: 1, frame: CGRect(x: 0, y: 0, width: 3000, height: 2000), layer: 0, ownerPID: 42),
        WindowCandidate(id: 2, frame: CGRect(x: 100, y: 100, width: 800, height: 600), layer: 0, ownerPID: 7,
                        ownerName: "Safari"),
        WindowCandidate(id: 3, frame: CGRect(x: 0, y: 0, width: 1512, height: 982), layer: 0, ownerPID: 8,
                        ownerName: "Finder"),
        WindowCandidate(id: 4, frame: CGRect(x: 120, y: 120, width: 10, height: 10), layer: 0, ownerPID: 9)
    ]

    @Test func picksTheFrontmostOrdinaryWindow() {
        // Exhibit A's own overlay (pid 42) is in front of everything and skipped.
        #expect(WindowPicker.pick(at: CGPoint(x: 200, y: 200), in: windows, excludingPID: 42)?.id == 2)
        #expect(WindowPicker.pick(at: CGPoint(x: 1000, y: 800), in: windows, excludingPID: 42)?.id == 3)
    }

    @Test func skipsMenuBarItemsAndTinyWindows() {
        #expect(WindowPicker.pick(at: CGPoint(x: 1410, y: 10), in: windows, excludingPID: 42)?.id == 3)
        #expect(WindowPicker.pick(at: CGPoint(x: 125, y: 125), in: windows, excludingPID: 42)?.id == 2)
    }

    @Test func nothingUnderThePointer() {
        #expect(WindowPicker.pick(at: CGPoint(x: 2000, y: 1500), in: windows, excludingPID: 42) == nil)
    }
}
