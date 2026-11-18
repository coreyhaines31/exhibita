import ExhibitCore
import ExhibitEditor
import PanelKit
import SwiftUI

/// What the editor's buttons do beyond the editor itself: the app's copy, save, path and close. Renders pass
/// no-ops.
struct EditorActions {
    var copyAndClose: () -> Void = {}
    var save: () -> Void = {}
    var copyPath: () -> Void = {}
    var close: () -> Void = {}

    func perform(_ command: EditorCommand) {
        switch command {
        case .copyAndClose: copyAndClose()
        case .save: save()
        case .copyPath: copyPath()
        case .close: close()
        default: break
        }
    }
}

/// The editor window's content: a thin metal toolbar that teaches the keys, the status strip, and the canvas
/// on a dark mount.
struct EditorView: View {
    let editor: CaptureEditor
    let canvas: EditorCanvasModel
    let actions: EditorActions
    /// Points per pixel of the capture; see `EditorLayout`.
    let pointsPerPixel: CGFloat
    /// Room on the left of the toolbar for the window's traffic lights. Renders without a window pass 0.
    var titlebarInset: CGFloat = 74

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 0) {
            EditorToolbar(editor: editor, actions: actions, leadingInset: titlebarInset)
            Rectangle().fill(Color.black.opacity(scheme == .dark ? 1 : 0.35)).frame(height: 1)
            ZStack {
                Color(white: scheme == .dark ? 0.06 : 0.16)
                EditorCanvas(editor: editor, canvas: canvas, pointsPerPixel: pointsPerPixel)
                    .padding(EditorLayout.mountPadding)
            }
        }
        .panelAccent(Brand.accent)
    }
}

/// Sizes shared by the window and the renders.
enum EditorLayout {
    static let toolbarHeight: CGFloat = 92
    static let mountPadding: CGFloat = 16
    static let minimumWidth: CGFloat = 820
    /// The share of the screen's visible area the window may take before the capture is scaled down.
    static let screenShare: CGFloat = 0.92

    /// Points per pixel so the capture shows at 1:1 (its own points) where it fits in `available`, scaled to
    /// fit otherwise. Never enlarged.
    static func pointsPerPixel(pixelSize: CGSize, scale: Double, available: CGSize) -> CGFloat {
        let natural = 1 / CGFloat(max(scale, 1))
        let room = CGSize(width: available.width - 2 * mountPadding,
                          height: available.height - toolbarHeight - 2 * mountPadding)
        guard pixelSize.width > 0, pixelSize.height > 0, room.width > 0, room.height > 0 else { return natural }
        return min(natural, room.width / pixelSize.width, room.height / pixelSize.height)
    }

    /// The window's content size for a capture shown at `pointsPerPixel`.
    static func contentSize(pixelSize: CGSize, pointsPerPixel: CGFloat) -> CGSize {
        CGSize(width: max(minimumWidth, pixelSize.width * pointsPerPixel + 2 * mountPadding),
               height: pixelSize.height * pointsPerPixel + 2 * mountPadding + toolbarHeight)
    }
}
