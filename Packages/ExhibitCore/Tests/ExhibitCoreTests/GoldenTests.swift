import CoreGraphics
@testable import ExhibitCore
import ExhibitFixtures
import Foundation
import Testing

/// Golden images for each mark at 1x and 2x. Run with `EXHIBIT_RECORD_GOLDENS=1` to rewrite them
/// (and `docs/samples/all-marks.png`), then look at every changed image before committing.
@Suite struct GoldenTests {
    static let recording = ProcessInfo.processInfo.environment["EXHIBIT_RECORD_GOLDENS"] == "1"
    static let goldens = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Goldens")
    static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    @Test(arguments: MarkKind.allCases, [1.0, 2.0])
    func markMatchesGolden(kind: MarkKind, scale: Double) throws {
        let fixture = goldenFixture(scale: scale)
        let output = try Renderer.render(original: fixture.image, marks: [goldenMark(kind, on: fixture)], scale: scale)
        try check(output, name: "\(kind.rawValue)@\(Int(scale))x.png")
    }

    @Test func allMarksSample() throws {
        let fixture = sampleFixture()
        let output = try Renderer.render(original: fixture.image, marks: sampleMarks(on: fixture), scale: fixture.scale)
        try check(output, name: "all-marks@2x.png")
        if Self.recording {
            let samples = Self.repoRoot.appendingPathComponent("docs/samples")
            try FileManager.default.createDirectory(at: samples, withIntermediateDirectories: true)
            try PNG.encode(output).write(to: samples.appendingPathComponent("all-marks.png"), options: .atomic)
        }
    }

    /// Every mark over the sample in Display P3, with bands of P3 colours sRGB cannot hold (issue 17).
    @Test func displayP3SampleMatchesGolden() throws {
        let fixture = sampleFixture()
        let width = fixture.image.width, height = fixture.image.height
        let original = makeImage(width: width, height: height, space: CGColorSpace.displayP3) { context in
            // The sample is drawn in an unflipped space here, so undo the helper's flip for it.
            context.saveGState()
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1, y: -1)
            context.draw(fixture.image, in: CGRect(x: 0, y: 0, width: width, height: height))
            context.restoreGState()
            let band = CGFloat(height) / 40
            let wideSpace = CGColorSpace(name: CGColorSpace.displayP3)!
            for (index, components) in [[1, 0, 0, 1], [0, 1, 0, 1], [0, 0, 1, 1] as [CGFloat]].enumerated() {
                context.setFillColor(CGColor(colorSpace: wideSpace, components: components)!)
                context.fill(CGRect(x: 0, y: CGFloat(height) - band * CGFloat(3 - index), width: CGFloat(width) / 3,
                                    height: band))
            }
        }
        let output = try Renderer.render(original: original, marks: sampleMarks(on: fixture), scale: fixture.scale)
        #expect(output.colorSpace?.isWideGamutRGB == true)
        try check(output, name: "all-marks-p3@2x.png", space: CGColorSpace.displayP3)
        if !Self.recording {
            let golden = try PNG.decode(Data(contentsOf: Self.goldens.appendingPathComponent("all-marks-p3@2x.png")))
            #expect(golden.colorSpace?.isWideGamutRGB == true, "the golden keeps its P3 profile")
        }
    }

    func check(_ output: CGImage, name: String, space: CFString = CGColorSpace.sRGB) throws {
        let url = Self.goldens.appendingPathComponent(name)
        if Self.recording {
            try FileManager.default.createDirectory(at: Self.goldens, withIntermediateDirectories: true)
            try PNG.encode(output).write(to: url, options: .atomic)
            return
        }
        let golden = try PNG.decode(Data(contentsOf: url))
        let difference = ImageDifference(Pixels(output, space: space), Pixels(golden, space: space))
        #expect(difference.sameSize, "\(name): size changed")
        // Text antialiasing can shift slightly between OS versions; anything bigger is a real change.
        #expect(difference.changedFraction <= 0.005,
                "\(name): \(difference.changedPixels) pixels differ; rerun with EXHIBIT_RECORD_GOLDENS=1 if intended")
    }
}

struct ImageDifference {
    let sameSize: Bool
    let changedPixels: Int
    let changedFraction: Double

    /// Counts pixels where any channel differs by more than `tolerance`.
    init(_ lhs: Pixels, _ rhs: Pixels, tolerance: Int = 2) {
        sameSize = lhs.width == rhs.width && lhs.height == rhs.height
        guard sameSize else {
            changedPixels = max(lhs.width * lhs.height, rhs.width * rhs.height)
            changedFraction = 1
            return
        }
        var changed = 0
        for pixel in 0..<(lhs.width * lhs.height) {
            let offset = pixel * 4
            for channel in 0..<4 where abs(Int(lhs.bytes[offset + channel]) - Int(rhs.bytes[offset + channel])) > tolerance {
                changed += 1
                break
            }
        }
        changedPixels = changed
        changedFraction = Double(changed) / Double(max(1, lhs.width * lhs.height))
    }
}
