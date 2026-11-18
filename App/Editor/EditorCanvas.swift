import ExhibitCore
import ExhibitEditor
import SwiftUI

/// The capture with its committed marks as `Renderer` draws them, plus light feedback on top: the shape being
/// dragged, the selection and its handles, and a caret in a label being typed. Pointer events go to the editor
/// in image pixels.
struct EditorCanvas: View {
    let editor: CaptureEditor
    let canvas: EditorCanvasModel
    /// Points on screen per pixel of the capture: 1 / scale at 1:1, less when scaled to fit.
    let pointsPerPixel: CGFloat

    @State private var dragging = false

    var body: some View {
        let size = CGSize(width: canvas.pixelSize.width * pointsPerPixel,
                          height: canvas.pixelSize.height * pointsPerPixel)
        ZStack(alignment: .topLeading) {
            if let rendered = canvas.rendered {
                Image(decorative: rendered, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: size.width, height: size.height)
                    .shadow(color: .black.opacity(0.5), radius: 8, y: 2)
            } else {
                Rectangle().fill(Color.black)
            }
            Canvas { context, _ in
                drawFeedback(in: &context)
            }
            .frame(width: size.width, height: size.height)
            .allowsHitTesting(false)
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .gesture(pointer)
        .task(id: editor.marks) { await canvas.refresh(editor.marks) }
        .accessibilityElement()
        .accessibilityLabel("Capture")
        .accessibilityValue(editor.marks.isEmpty ? "No marks" : "\(editor.marks.count) marks")
    }

    private var pointer: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                if !dragging {
                    dragging = true
                    editor.pointerDown(at: pixel(value.startLocation))
                }
                editor.pointerDragged(to: pixel(value.location))
            }
            .onEnded { value in
                if !dragging { editor.pointerDown(at: pixel(value.startLocation)) }
                dragging = false
                editor.pointerUp(at: pixel(value.location))
            }
    }

    private func pixel(_ point: CGPoint) -> PixelPoint {
        PixelPoint(x: point.x / pointsPerPixel, y: point.y / pointsPerPixel)
    }

    private func rect(_ rect: PixelRect) -> CGRect {
        CGRect(x: rect.minX * pointsPerPixel, y: rect.minY * pointsPerPixel,
               width: (rect.maxX - rect.minX) * pointsPerPixel, height: (rect.maxY - rect.minY) * pointsPerPixel)
    }

    private func point(_ point: PixelPoint) -> CGPoint {
        CGPoint(x: point.x * pointsPerPixel, y: point.y * pointsPerPixel)
    }

    // MARK: - Feedback

    private func drawFeedback(in context: inout GraphicsContext) {
        if let draft = editor.draft {
            drawDraft(draft, in: &context)
        } else if let box = editor.selectionBox, editor.editingTextID == nil {
            // An arrow's box is mostly empty; its two handles say enough.
            if editor.selectedMark?.kind != .arrow { drawOutline(rect(box).insetBy(dx: -4, dy: -4), in: &context) }
            for handle in editor.selectedHandles {
                let center = point(handle)
                let square = CGRect(x: center.x - 4, y: center.y - 4, width: 8, height: 8)
                context.fill(Path(roundedRect: square, cornerRadius: 1.5), with: .color(.white))
                context.stroke(Path(roundedRect: square, cornerRadius: 1.5), with: .color(.black.opacity(0.7)),
                               lineWidth: 1)
            }
        }
        if let editing = editor.editingMark {
            drawCaret(for: editing, in: &context)
        }
    }

    private func drawOutline(_ outline: CGRect, in context: inout GraphicsContext) {
        context.stroke(Path(roundedRect: outline, cornerRadius: 3), with: .color(.white), style: StrokeStyle(lineWidth: 3))
        context.stroke(Path(roundedRect: outline, cornerRadius: 3), with: .color(.black.opacity(0.75)),
                       style: StrokeStyle(lineWidth: 1.25, dash: [4, 3]))
    }

    private func drawDraft(_ draft: EditorDraft, in context: inout GraphicsContext) {
        let color = draft.color.swatch
        let lineWidth = max(1.5, 3 * editor.document.scale * pointsPerPixel)
        switch (draft.kind, draft.geometry) {
        case let (.arrow, .line(from, to)):
            var path = Path()
            path.move(to: point(from))
            path.addLine(to: point(to))
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: lineWidth + 1, lineCap: .round))
            context.fill(Path(ellipseIn: CGRect(x: point(to).x - 4, y: point(to).y - 4, width: 8, height: 8)),
                         with: .color(color))
        case (.circle, _):
            context.stroke(Path(ellipseIn: rect(editor.visibleBox(of: draft.mark))), with: .color(color),
                           lineWidth: lineWidth)
        case (.box, _):
            context.stroke(Path(roundedRect: rect(draft.mark.bounds), cornerRadius: 4), with: .color(color),
                           lineWidth: lineWidth)
        case (.highlight, _):
            context.fill(Path(rect(draft.mark.bounds)), with: .color(color.opacity(0.35)))
        case (.blur, _):
            // A stand-in until the pointer comes up; the committed blur is the renderer's redaction.
            let box = rect(draft.mark.bounds)
            context.fill(Path(box), with: .color(Color(white: 0.6).opacity(0.85)))
            context.stroke(Path(box), with: .color(.white), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
        default:
            let box = rect(editor.visibleBox(of: draft.mark))
            context.stroke(Path(roundedRect: box, cornerRadius: 4), with: .color(color),
                           style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
        }
    }

    private func drawCaret(for mark: Mark, in context: inout GraphicsContext) {
        let box = rect(editor.visibleBox(of: mark))
        let unit = editor.layout.unit * pointsPerPixel
        let empty = (mark.style.label ?? "").isEmpty
        if empty {
            let hint = Text("Type a label, then ↩")
                .font(.system(size: max(10, 13 * unit), weight: .semibold))
                .foregroundColor(.white)
            let resolved = context.resolve(hint)
            let size = resolved.measure(in: CGSize(width: 1000, height: 100))
            let pill = CGRect(x: box.minX, y: box.minY, width: size.width + 16 * unit, height: box.height)
            context.fill(Path(roundedRect: pill, cornerRadius: 6 * unit),
                         with: .color(mark.style.color.swatch.opacity(0.55)))
            context.draw(resolved, at: CGPoint(x: pill.minX + 8 * unit, y: pill.midY), anchor: .leading)
            return
        }
        let x = box.maxX - 7 * unit
        var caret = Path()
        caret.move(to: CGPoint(x: x, y: box.minY + 4 * unit))
        caret.addLine(to: CGPoint(x: x, y: box.maxY - 4 * unit))
        context.stroke(caret, with: .color(mark.style.color.onSwatch), lineWidth: max(1, 1.5 * unit))
    }
}

extension MarkColor {
    /// The renderer's mark colours (`MarkColor.rgb` in ExhibitCore), for feedback drawn over the canvas.
    var swatch: Color {
        switch self {
        case .red: Color(.sRGB, red: 1.0, green: 0.231, blue: 0.188)
        case .yellow: Color(.sRGB, red: 1.0, green: 0.8, blue: 0.0)
        case .blue: Color(.sRGB, red: 0.039, green: 0.518, blue: 1.0)
        case .green: Color(.sRGB, red: 0.204, green: 0.78, blue: 0.349)
        }
    }

    var onSwatch: Color {
        self == .yellow ? Color(white: 0.11) : .white
    }
}
