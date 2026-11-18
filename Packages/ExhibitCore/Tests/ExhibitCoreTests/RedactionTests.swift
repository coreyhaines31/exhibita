import CoreGraphics
@testable import ExhibitCore
import Foundation
import ImageIO
import Testing

/// The blocking security requirement: nothing under a blur survives into the output.
@Suite struct RedactionTests {
    /// A light UI-like background with the same surroundings every time, and `secret` drawn inside `area`.
    func capture(secret: UInt64, area: CGRect, width: Int = 320, height: Int = 200) -> CGImage {
        makeImage(width: width, height: height) { context in
            context.setFillColor(CGColor(srgbRed: 0.97, green: 0.97, blue: 0.98, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.setFillColor(CGColor(srgbRed: 0.2, green: 0.4, blue: 0.9, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: 24))
            context.setFillColor(CGColor(gray: 0.3, alpha: 1))
            for row in 0..<6 {
                context.fill(CGRect(x: 16, y: 40 + row * 24, width: 140 + row * 17 % 60, height: 8))
            }
            // Pseudo-random strokes standing in for different secret text, covering every pixel of the area.
            context.clip(to: area.integral)
            var state = secret
            for _ in 0..<400 {
                state = Patch.mix(state)
                let x = area.minX - 4 + Double(state % 1000) / 1000 * (area.width + 8)
                let y = area.minY - 4 + Double((state >> 12) % 1000) / 1000 * (area.height + 8)
                let gray = Double((state >> 24) % 256) / 255
                context.setFillColor(CGColor(srgbRed: gray, green: 1 - gray, blue: gray / 2, alpha: 1))
                context.fill(CGRect(x: x, y: y, width: 3, height: 3))
            }
        }
    }

    let allMarks: [Mark] = [
        .highlight(PixelRect(x: 14, y: 36, width: 120, height: 16)),
        .box(PixelRect(x: 10, y: 60, width: 150, height: 40), color: .blue),
        .circle(PixelRect(x: 180, y: 40, width: 50, height: 20), color: .green),
        .arrow(from: PixelPoint(x: 290, y: 180), to: PixelPoint(x: 230, y: 135), label: "Here"),
        .text("Label", at: PixelPoint(x: 20, y: 150), color: .yellow),
        .step(1, at: PixelPoint(x: 290, y: 50))
    ]

    @Test func outputUnderABlurDoesNotDependOnTheOriginal() throws {
        let rect = PixelRect(x: 170.4, y: 100.6, width: 90.3, height: 22.2)
        let marks = allMarks + [.blur(rect)]
        let first = capture(secret: 1, area: rect.cgRect)
        let second = capture(secret: 2, area: rect.cgRect)
        #expect(Pixels(first) != Pixels(second), "the fixtures must differ under the blur")
        #expect(Pixels(first).region(CGRect(x: 0, y: 0, width: 320, height: 100)) ==
                Pixels(second).region(CGRect(x: 0, y: 0, width: 320, height: 100)),
                "the fixtures must not differ outside the blur")

        let outFirst = try Renderer.render(original: first, marks: marks, scale: 1)
        let outSecond = try Renderer.render(original: second, marks: marks, scale: 1)
        #expect(Pixels(outFirst).region(rect.cgRect) == Pixels(outSecond).region(rect.cgRect))
        #expect(Pixels(outFirst) == Pixels(outSecond))
        #expect(try PNG.encode(outFirst) == PNG.encode(outSecond))
    }

    @Test func holdsAtTwoTimesAndForOverlappingAndEdgeBlurs() throws {
        let rects = [
            PixelRect(x: 40, y: 60, width: 80, height: 20),
            PixelRect(x: 100, y: 70, width: 90, height: 30),
            PixelRect(x: 590, y: 380, width: 80, height: 40),
            PixelRect(x: -10, y: -10, width: 50, height: 30)
        ]
        let first = layered(secret: 10, rects: rects)
        let second = layered(secret: 20, rects: rects)
        #expect(Pixels(first) != Pixels(second))
        let marks = rects.map { Mark.blur($0) }
        #expect(Pixels(try Renderer.render(original: first, marks: marks, scale: 2)) ==
                Pixels(try Renderer.render(original: second, marks: marks, scale: 2)))
    }

    /// One image where each rect holds noise from `secret`, over identical surroundings.
    func layered(secret: UInt64, rects: [PixelRect]) -> CGImage {
        let base = capture(secret: 0, area: .zero, width: 640, height: 400)
        var pixels = Pixels(base).bytes
        var state = secret
        for rect in rects {
            guard let area = PixelArea(rect, width: 640, height: 400) else { continue }
            for y in area.minY..<area.maxY {
                for x in area.minX..<area.maxX {
                    state = Patch.mix(state)
                    let offset = (y * 640 + x) * 4
                    pixels[offset] = UInt8(state & 0xFF)
                    pixels[offset + 1] = UInt8((state >> 8) & 0xFF)
                    pixels[offset + 2] = UInt8((state >> 16) & 0xFF)
                    pixels[offset + 3] = 255
                }
            }
        }
        return image(from: pixels, width: 640, height: 400)
    }

    @Test func aBlurOverTheWholeImageOrWithNaNHidesEverything() throws {
        let first = capture(secret: 3, area: CGRect(x: 0, y: 0, width: 320, height: 200))
        let second = capture(secret: 4, area: CGRect(x: 0, y: 0, width: 320, height: 200))
        for rect in [PixelRect(x: -5, y: -5, width: 400, height: 300), PixelRect(x: .nan, y: 0, width: 10, height: 10),
                     PixelRect(x: 0, y: 0, width: .nan, height: 10)] {
            #expect(Pixels(try Renderer.render(original: first, marks: [.blur(rect)])) ==
                    Pixels(try Renderer.render(original: second, marks: [.blur(rect)])))
        }
    }

    @Test func theSecretIsGone() throws {
        let rect = PixelRect(x: 40, y: 60, width: 120, height: 20)
        let original = makeImage(width: 240, height: 140) { context in
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 240, height: 140))
            context.setFillColor(CGColor(gray: 0, alpha: 1))
            for index in 0..<12 {
                context.fill(CGRect(x: 44 + index * 10, y: 64, width: 5, height: 12))
            }
        }
        let region = Pixels(try Renderer.render(original: original, marks: [.blur(rect)], scale: 1)).region(rect.cgRect)
        let darkest = stride(from: 0, to: region.count, by: 4).map { Int(region[$0]) }.min() ?? 0
        #expect(darkest > 200, "no dark text pixel survives under the blur")
    }

    @Test func exportedPNGHoldsOneFlatImageAndNoExtraData() throws {
        let rect = PixelRect(x: 170, y: 100, width: 90, height: 22)
        let png = try Renderer.renderPNG(original: capture(secret: 5, area: rect.cgRect),
                                         marks: allMarks + [.blur(rect)], scale: 1)
        let source = try #require(CGImageSourceCreateWithData(png as CFData, nil))
        #expect(CGImageSourceGetCount(source) == 1)
        #expect(CGImageSourceGetPrimaryImageIndex(source) == 0)
        for auxiliary in [kCGImageAuxiliaryDataTypeDepth, kCGImageAuxiliaryDataTypeDisparity,
                          kCGImageAuxiliaryDataTypePortraitEffectsMatte] {
            #expect(CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, auxiliary) == nil)
        }
        let allowed: Set<String> = ["IHDR", "sRGB", "iCCP", "gAMA", "cHRM", "pHYs", "IDAT", "IEND"]
        let chunks = pngChunkTypes(png)
        #expect(Set(chunks).isSubset(of: allowed), "unexpected chunks: \(chunks)")
        #expect(chunks.first == "IHDR" && chunks.last == "IEND")
    }
}

func image(from rgba: [UInt8], width: Int, height: Int) -> CGImage {
    let provider = CGDataProvider(data: Data(rgba) as CFData)!
    return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                   space: CGColorSpace(name: CGColorSpace.sRGB)!,
                   bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                   provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
}

/// The chunk type of every chunk in a PNG file, in order.
func pngChunkTypes(_ data: Data) -> [String] {
    let bytes = [UInt8](data)
    var types: [String] = []
    var offset = 8
    while offset + 8 <= bytes.count {
        let length = bytes[offset..<offset + 4].reduce(0) { $0 << 8 | Int($1) }
        types.append(String(bytes: bytes[offset + 4..<offset + 8], encoding: .ascii) ?? "????")
        offset += 12 + length
    }
    return types
}
