import AppKit
@testable import ExhibitA
import ExhibitCore
import ExhibitEditor
import XCTest

/// One open editor window, driven like a person would: keys, clicks and drags in image pixels, converted to
/// window points through the canvas the editor laid out.
@MainActor
struct EditorDriver {
    let controller: EditorWindowController
    let window: EditorWindow
    let map: CanvasMap

    init(_ controller: EditorWindowController) throws {
        self.controller = controller
        window = try XCTUnwrap(controller.window)
        let original = controller.editor.document.size
        map = try CanvasMap(window: window, topLeftFrame: controller.canvas.frameInWindow,
                            pixelSize: CGSize(width: original.width, height: original.height))
    }

    var editor: CaptureEditor { controller.editor }
    var id: UUID { editor.document.id }

    func key(_ character: Character, _ modifiers: NSEvent.ModifierFlags = []) async {
        Events.key(character, modifiers, in: window)
        await E2E.settle(30)
    }

    func special(_ code: UInt16, _ modifiers: NSEvent.ModifierFlags = []) async {
        Events.special(code, modifiers, in: window)
        await E2E.settle(30)
    }

    func type(_ text: String) async {
        Events.type(text, in: window)
        await E2E.settle(30)
    }

    func click(_ pixel: PixelPoint, count: Int = 1) async {
        Events.click(at: map.point(pixel), in: window, count: count)
        await E2E.settle(30)
    }

    func click(_ rect: PixelRect) async {
        await click(PixelPoint(x: rect.midX, y: rect.midY))
    }

    func drag(_ from: PixelPoint, _ to: PixelPoint) async {
        Events.drag(from: map.point(from), to: map.point(to), in: window)
        await E2E.settle(30)
    }

    /// The first target whose text contains `text`, or of `kind`.
    func target(containing text: String) throws -> Target {
        try XCTUnwrap(editor.document.targets.first { $0.text?.localizedCaseInsensitiveContains(text) == true },
                      "a target reading \(text) in \(editor.document.targets.compactMap(\.text))")
    }

    func target(_ kind: TargetKind) throws -> Target {
        try XCTUnwrap(editor.document.targets.first { $0.kind == kind }, "a \(kind) target")
    }

    /// Waits for the canvas to show the current marks, then pictures the window's content.
    func picture(named name: String) async throws {
        await E2E.settle(400)
        let content = try XCTUnwrap(window.contentView)
        let url = try E2E.picture(content, named: name)
        print("E2E: picture \(url.path)")
    }

    func waitForClose() async {
        await E2E.wait("the editor to close") { !window.isVisible && E2E.editors.windows[id] == nil }
    }
}

/// Raw RGBA8 pixels of an image in sRGB, to compare regions.
struct Pixels: Equatable {
    let width: Int
    let height: Int
    let bytes: [UInt8]

    init(_ image: CGImage) {
        width = image.width
        height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
                                    bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            context?.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        self.bytes = bytes
    }

    /// The bytes inside `rect` (top-left origin), row by row.
    func region(_ rect: PixelRect) -> [UInt8] {
        let minX = max(0, Int(rect.minX.rounded(.down)))
        let maxX = min(width, Int(rect.maxX.rounded(.up)))
        let minY = max(0, Int(rect.minY.rounded(.down)))
        let maxY = min(height, Int(rect.maxY.rounded(.up)))
        var out: [UInt8] = []
        for row in minY..<maxY {
            let start = (row * width + minX) * 4
            out += bytes[start..<(start + (maxX - minX) * 4)]
        }
        return out
    }
}

extension Mark {
    /// What a mark looks like, without its id, for comparing marks made two ways.
    var shape: String {
        "\(kind.rawValue) \(geometry) \(style.color.rawValue) \(style.label ?? "") \(style.stepNumber ?? 0)"
    }
}

extension PixelRect {
    func contains(_ point: PixelPoint, slack: Double = 0) -> Bool {
        point.x >= minX - slack && point.x <= maxX + slack && point.y >= minY - slack && point.y <= maxY + slack
    }

    func intersects(_ other: PixelRect) -> Bool {
        cgRect.intersects(other.cgRect)
    }
}
