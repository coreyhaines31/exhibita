import CoreGraphics
@testable import ExhibitCLI
import ExhibitCore
import ExhibitFixtures
import Foundation
import ImageIO
import Testing

/// A fresh directory under the system temporary directory.
func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("ExhibitCLITests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// Writes `fixture` as a PNG in `directory` and returns its path.
@discardableResult
func writePNG(_ fixture: Fixture, named name: String, in directory: URL) throws -> String {
    let url = directory.appendingPathComponent(name)
    try PNG.encode(fixture.image).write(to: url)
    return url.path
}

/// Writes `fixture` as a high quality JPEG in `directory` and returns its path.
func writeJPEG(_ fixture: Fixture, named name: String, in directory: URL) throws -> String {
    let url = directory.appendingPathComponent(name)
    let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil))
    CGImageDestinationAddImage(destination, fixture.image,
                               [kCGImageDestinationLossyCompressionQuality: 0.95] as CFDictionary)
    #expect(CGImageDestinationFinalize(destination))
    return url.path
}

func readImage(_ path: String) throws -> CGImage {
    try PNG.decode(try Data(contentsOf: URL(fileURLWithPath: path)))
}

func json(_ text: String) throws -> [String: Any] {
    try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
}

/// The `error` object of a failed result.
func errorBody(_ result: CLIResult) throws -> [String: Any] {
    try #require(try json(result.stderr)["error"] as? [String: Any])
}

func marks(_ result: CLIResult) throws -> [[String: Any]] {
    try #require(try json(result.stdout)["marks"] as? [[String: Any]])
}

func rect(_ object: Any?) throws -> PixelRect {
    let values = try #require(object as? [String: Double])
    return PixelRect(x: values["x"] ?? .nan, y: values["y"] ?? .nan, width: values["width"] ?? .nan,
                     height: values["height"] ?? .nan)
}

func point(_ object: Any?) throws -> PixelPoint {
    let values = try #require(object as? [String: Double])
    return PixelPoint(x: values["x"] ?? .nan, y: values["y"] ?? .nan)
}

private final class BundleMarker {}

/// Runs the built `exhibit` binary, as an agent would, with `input` on its standard input.
func runBinary(_ arguments: [String], input: String? = nil) throws -> CLIResult {
    // The test bundle sits in the products directory beside the binary `swift test` built.
    let products = Bundle(for: BundleMarker.self).bundleURL.deletingLastPathComponent()
    let process = Process()
    process.executableURL = products.appendingPathComponent("exhibit")
    process.arguments = arguments
    let stdout = Pipe()
    let stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr
    let stdin = Pipe()
    process.standardInput = stdin
    try process.run()
    if let input { stdin.fileHandleForWriting.write(Data(input.utf8)) }
    try stdin.fileHandleForWriting.close()
    let out = stdout.fileHandleForReading.readDataToEndOfFile()
    let err = stderr.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    let status = try #require(ExitStatus(rawValue: process.terminationStatus), "exit \(process.terminationStatus)")
    return CLIResult(status: status, stdout: String(bytes: out, encoding: .utf8) ?? "",
                     stderr: String(bytes: err, encoding: .utf8) ?? "")
}

/// RGBA8 bytes of `rect` (whole pixels, top-left origin) of `image`.
func pixels(of image: CGImage, in rect: CGRect) throws -> [UInt8] {
    let width = Int(rect.width)
    let height = Int(rect.height)
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
    try bytes.withUnsafeMutableBytes { raw in
        let context = try #require(CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                             bytesPerRow: width * 4, space: space,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        // Shift so `rect`'s top-left lands at the context's top-left (CoreGraphics' origin is bottom-left).
        context.draw(image, in: CGRect(x: -rect.minX, y: rect.maxY - Double(image.height), width: Double(image.width),
                                       height: Double(image.height)))
    }
    return bytes
}
