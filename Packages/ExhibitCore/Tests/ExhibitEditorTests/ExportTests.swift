import CoreGraphics
import ExhibitCore
@testable import ExhibitEditor
import ExhibitFixtures
import ExhibitShell
import Foundation
import Testing

@MainActor
@Suite struct ExportTests {
    let fixture = EditorFixture()

    /// The spec's example: drag (already captured), B, click the email, A, drag to the button, ↩.
    @Test func sevenKeystrokeExample() throws {
        let editor = makeEditor(fixture)
        editor.press("b")
        editor.click(fixture.point(in: fixture["email"]))
        editor.press("a")
        editor.drag(from: PixelPoint(x: 1000, y: 760), to: fixture.point(in: fixture["update"]))
        #expect(editor.handle(.returnKey) == .app(.copyAndClose))

        #expect(editor.marks.map(\.kind) == [.blur, .arrow])
        #expect(editor.marks[0].targetID == fixture.emailID)
        #expect(editor.marks[1].targetID == fixture.updateID)
        #expect(editor.status == .secrets(1), "the key is still counted, quietly")
    }

    @Test func exportIsTheRenderersBytes() throws {
        let editor = makeEditor(fixture)
        editor.press("b")
        editor.click(fixture.point(in: fixture["email"]))
        editor.press("h")
        editor.click(fixture.point(in: fixture["renews"]))
        editor.press("t")
        editor.click(PixelPoint(x: 900, y: 120))
        editor.press("Here")
        _ = editor.handle(.returnKey)

        let exported = try EditorExport.png(editor.document, original: fixture.fixture.image)
        let rendered = try PNG.encode(Renderer.render(original: fixture.fixture.image, marks: editor.marks,
                                                      scale: fixture.document.scale))
        #expect(exported == rendered)
    }

    /// Two captures that differ only under the blur export to the same bytes, so nothing under it leaks.
    @Test func exportUnderABlurDoesNotDependOnTheOriginal() throws {
        let editor = makeEditor(fixture)
        editor.press("b")
        editor.click(fixture.point(in: fixture["email"]))
        let blur = try #require(editor.marks.only).bounds

        let original = fixture.fixture.image
        // Both copies go through the same context, so they differ only where the second is painted over.
        func copy(paintingUnderBlur: Bool) -> CGImage {
            makeImage(width: original.width, height: original.height) { context in
                // `makeImage` flips to top-left coordinates, so undo that for the image itself.
                context.saveGState()
                context.translateBy(x: 0, y: CGFloat(original.height))
                context.scaleBy(x: 1, y: -1)
                context.draw(original, in: CGRect(x: 0, y: 0, width: original.width, height: original.height))
                context.restoreGState()
                guard paintingUnderBlur else { return }
                context.setFillColor(CGColor(red: 1, green: 0, blue: 1, alpha: 1))
                context.fill(CGRect(x: blur.minX + 2, y: blur.minY + 2, width: blur.width - 4, height: blur.height - 4))
            }
        }
        let image = copy(paintingUnderBlur: false)
        let tampered = copy(paintingUnderBlur: true)
        #expect(try PNG.encode(image) != PNG.encode(tampered))
        let first = try EditorExport.png(editor.document, original: image)
        let second = try EditorExport.png(editor.document, original: tampered)
        #expect(first == second)
    }

    @Test func exportsCarryNoMetadata() throws {
        let png = try EditorExport.png(fixture.document, original: fixture.fixture.image)
        let chunks = chunkTypes(png)
        #expect(chunks.first == "IHDR")
        #expect(chunks.last == "IEND")
        #expect(!chunks.contains("eXIf") && !chunks.contains("tEXt") && !chunks.contains("iTXt"))
    }

    @Test func fileNamesFollowTheCLI() throws {
        var document = fixture.document
        document.createdAt = Date(timeIntervalSince1970: 1_795_016_467)
        let utc = try #require(TimeZone(identifier: "UTC"))
        #expect(EditorExport.fileName(for: document, timeZone: utc) == "Safari 2026-11-18 at 15.41.07-marked.png")
        document.source = nil
        #expect(EditorExport.fileName(for: document, timeZone: utc) == "Capture 2026-11-18 at 15.41.07-marked.png")
        document.source = CaptureSource(appName: "a/b:c")
        #expect(EditorExport.fileName(for: document, timeZone: utc).hasPrefix("a-b-c "))
    }

    @Test func writesTheFile() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ExhibitEditorTests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = try EditorExport.write(Data([1, 2, 3]), named: "x-marked.png", in: folder)
        #expect(try Data(contentsOf: url) == Data([1, 2, 3]))
    }

    private func chunkTypes(_ png: Data) -> [String] {
        let bytes = [UInt8](png)
        var types: [String] = []
        var offset = 8
        while offset + 12 <= bytes.count {
            let length = bytes[offset..<offset + 4].reduce(0) { $0 << 8 | Int($1) }
            types.append(String(bytes: bytes[offset + 4..<offset + 8], encoding: .ascii) ?? "")
            offset += 12 + length
        }
        return types
    }
}
