import CoreGraphics
@testable import ExhibitCore
import Foundation
import Testing

@Suite struct CaptureBundleTests {
    let original = makeImage(width: 64, height: 48) { context in
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 64, height: 48))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 8, y: 8, width: 20, height: 6))
    }

    func document() -> CaptureDocument {
        CaptureDocument(size: PixelSize(width: 64, height: 48), scale: 2,
                        source: CaptureSource(appName: "Notes", capturedBy: .person),
                        targets: [Target(kind: .text, text: "Hello", rect: PixelRect(x: 8, y: 8, width: 20, height: 6))],
                        marks: [.box(PixelRect(x: 4, y: 4, width: 30, height: 14))])
    }

    @Test func savesAndLoadsABundle() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let doc = document()
        let url = try CaptureBundle.save(doc, original: original, in: directory)
        #expect(url.lastPathComponent == "\(doc.id.uuidString).exhibit")
        let contents = try FileManager.default.contentsOfDirectory(atPath: url.path).sorted()
        #expect(contents == ["document.json", "original.png"])
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == [url.lastPathComponent])

        let loaded = try CaptureBundle.load(from: url)
        #expect(loaded.document == doc)
        #expect(Pixels(loaded.original) == Pixels(original))
    }

    @Test func updatesTheDocumentInPlace() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var doc = document()
        let url = try CaptureBundle.save(doc, original: original, in: directory)
        doc.marks.append(.step(1, at: PixelPoint(x: 40, y: 30)))
        try CaptureBundle.saveDocument(doc, to: url)
        #expect(try CaptureBundle.load(from: url).document.marks.count == 2)
        doc.marks.removeAll()
        try CaptureBundle.save(doc, original: original, in: directory)
        #expect(try CaptureBundle.load(from: url).document.marks.isEmpty)
    }

    @Test func encodingIsStable() throws {
        let doc = document()
        #expect(try CaptureBundle.encode(doc) == CaptureBundle.encode(doc))
        let json = String(bytes: try CaptureBundle.encode(doc), encoding: .utf8) ?? ""
        #expect(json.contains("\"formatVersion\" : 1"))
    }

    @Test func refusesAFutureFormatVersion() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try CaptureBundle.save(document(), original: original, in: directory)
        let documentURL = url.appendingPathComponent(CaptureBundle.documentFileName)
        let json = String(bytes: try Data(contentsOf: documentURL), encoding: .utf8) ?? ""
        // A future version may change anything else, so only the version needs to parse.
        let future = json.replacingOccurrences(of: "\"formatVersion\" : 1", with: "\"formatVersion\" : 2")
            .replacingOccurrences(of: "\"marks\"", with: "\"layers\"")
        try Data(future.utf8).write(to: documentURL)
        #expect(throws: ExhibitError.unsupportedFormatVersion(found: 2, supported: 1)) {
            try CaptureBundle.load(from: url)
        }
        #expect(ExhibitError.unsupportedFormatVersion(found: 2, supported: 1).description.contains("Update Exhibit A"))
    }

    @Test func reportsMissingFilesAndSizeMismatches() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(throws: ExhibitError.missingFile("document.json")) {
            try CaptureBundle.load(from: directory.appendingPathComponent("nope.exhibit"))
        }
        var wrong = document()
        wrong.size = PixelSize(width: 10, height: 10)
        #expect(throws: ExhibitError.sizeMismatch(document: wrong.size, image: PixelSize(width: 64, height: 48))) {
            try CaptureBundle.save(wrong, original: original, in: directory)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }
}
