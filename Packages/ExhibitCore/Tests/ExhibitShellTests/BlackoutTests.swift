import CoreGraphics
import ExhibitCore
import ExhibitShell
import Foundation
import Testing

@Suite struct BlackoutTests {
    let vault = WindowCandidate(id: 1, frame: CGRect(x: 150, y: 120, width: 200, height: 100), layer: 0,
                                ownerPID: 10, ownerName: "Keychain Access",
                                bundleIdentifier: "com.apple.keychainaccess")
    let safari = WindowCandidate(id: 2, frame: CGRect(x: 0, y: 0, width: 400, height: 300), layer: 0, ownerPID: 11,
                                 ownerName: "Safari", bundleIdentifier: "com.apple.Safari")

    @Test func mapsListedWindowsToPixelsOfTheCapture() {
        // A 2x capture of the region (100, 100) to (500, 400) in global points.
        let regions = Blackout.regions(windows: [safari, vault], policy: CapturePolicy(),
                                       captureRect: CGRect(x: 100, y: 100, width: 400, height: 300),
                                       pixelSize: PixelSize(width: 800, height: 600))
        #expect(regions == [Blackout.Region(rect: PixelRect(x: 100, y: 40, width: 400, height: 200),
                                            reason: "Keychain Access is on the never-capture list")])
    }

    @Test func clipsToTheImageGrowsToWholePixelsAndDropsWindowsOutside() {
        let partly = WindowCandidate(id: 3, frame: CGRect(x: 90.25, y: 95.5, width: 30, height: 20), layer: 0,
                                     ownerPID: 12, ownerName: "1Password")
        let outside = WindowCandidate(id: 4, frame: CGRect(x: 900, y: 900, width: 30, height: 20), layer: 0,
                                      ownerPID: 13, ownerName: "Bitwarden")
        let regions = Blackout.regions(windows: [partly, outside], policy: CapturePolicy(),
                                       captureRect: CGRect(x: 100, y: 100, width: 400, height: 300),
                                       pixelSize: PixelSize(width: 400, height: 300))
        #expect(regions.map(\.rect) == [PixelRect(x: 0, y: 0, width: 21, height: 16)])
    }

    @Test func nothingListedNothingBlackedOut() {
        let regions = Blackout.regions(windows: [vault], policy: CapturePolicy(neverCapture: []),
                                       captureRect: CGRect(x: 0, y: 0, width: 400, height: 300),
                                       pixelSize: PixelSize(width: 400, height: 300))
        #expect(regions.isEmpty)
    }

    @Test func paintsRegionsSolidBlackAndLeavesTheRest() throws {
        let image = try solid(width: 600, height: 300, gray: 1)
        let region = Blackout.Region(rect: PixelRect(x: 10, y: 20, width: 500, height: 200),
                                     reason: "Keychain Access is on the never-capture list")
        let painted = try Blackout.paint(image, regions: [region], scale: 1)
        let pixels = try gray(painted)
        // Corners of the region are black (the label sits in the middle), outside is untouched.
        #expect(pixels(12, 22) == 0)
        #expect(pixels(507, 217) == 0)
        #expect(pixels(5, 5) == 255)
        #expect(pixels(520, 150) == 255)
        // The label is drawn: some pixels in the middle row band are not black.
        let labelled = (100..<420).contains { x in (110..<130).contains { y in pixels(x, y) > 100 } }
        #expect(labelled)
    }

    func solid(width: Int, height: Int, gray: CGFloat) throws -> CGImage {
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                             bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: gray, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try #require(context.makeImage())
    }

    /// Reads the red channel at top-left pixel coordinates.
    func gray(_ image: CGImage) throws -> (Int, Int) -> UInt8 {
        let width = image.width
        let height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let context = try #require(CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8,
                                             bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let copy = bytes
        return { x, y in copy[(y * width + x) * 4] }
    }
}

@Suite struct WindowQueryTests {
    func window(_ id: UInt32, _ app: String, _ title: String?, pid: Int32, bundle: String? = nil,
                layer: Int = 0, side: CGFloat = 300) -> WindowCandidate {
        WindowCandidate(id: id, frame: CGRect(x: 0, y: 0, width: side, height: side), layer: layer, ownerPID: pid,
                        ownerName: app, title: title, bundleIdentifier: bundle)
    }

    var windows: [WindowCandidate] {
        [
            window(1, "Exhibit A", "Panel", pid: 99),
            window(2, "Safari", "Pricing - Example", pid: 1, bundle: "com.apple.Safari"),
            window(3, "Safari", "Docs - Example", pid: 1, bundle: "com.apple.Safari"),
            window(4, "Notes", "Pricing ideas", pid: 2),
            window(5, "Terminal", "zsh", pid: 3),
            window(6, "Terminal Helper", nil, pid: 4),
            window(7, "Dock", "Dock", pid: 5, layer: 20),
            window(8, "Tiny", "tiny", pid: 6, side: 10)
        ]
    }

    @Test func appNameOrBundleIdentifierPicksTheFrontmostWindow() {
        #expect(WindowQuery.match("safari", in: windows, excludingPID: 99) == .found(windows[1]))
        #expect(WindowQuery.match("com.apple.Safari", in: windows, excludingPID: 99) == .found(windows[1]))
    }

    @Test func titlesExactThenContained() {
        #expect(WindowQuery.match("Docs - Example", in: windows, excludingPID: 99) == .found(windows[2]))
        #expect(WindowQuery.match("pricing", in: windows, excludingPID: 99) == .ambiguous([windows[1], windows[3]]))
        #expect(WindowQuery.match("ideas", in: windows, excludingPID: 99) == .found(windows[3]))
    }

    @Test func partialAppNames() {
        #expect(WindowQuery.match("Term", in: windows, excludingPID: 99) == .ambiguous([windows[4], windows[5]]))
        #expect(WindowQuery.match("Note", in: windows, excludingPID: 99) == .found(windows[3]))
    }

    @Test func skipsOwnLayeredTinyAndUnknown() {
        #expect(WindowQuery.match("Panel", in: windows, excludingPID: 99) == .notFound)
        #expect(WindowQuery.match("Dock", in: windows, excludingPID: 99) == .notFound)
        #expect(WindowQuery.match("tiny", in: windows, excludingPID: 99) == .notFound)
        #expect(WindowQuery.match("Figma", in: windows, excludingPID: 99) == .notFound)
        #expect(WindowQuery.match("  ", in: windows, excludingPID: 99) == .notFound)
    }
}
