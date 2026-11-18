import ExhibitCore
import Foundation

/// A pointer gesture in progress.
enum EditorGesture {
    case draw(EditorTool, start: PixelPoint)
    case move(Mark, start: PixelPoint)
    case resize(Mark, MarkHandle)
}

/// Pointer events in image pixels, and what each tool makes of a click or a drag.
extension CaptureEditor {
    // MARK: - Pointer

    public func pointerDown(at point: PixelPoint) {
        notice = nil
        commitText()
        if let selected = selectedMark, let handle = hitTesting.handle(at: point, of: selected) {
            gesture = .resize(selected, handle)
            return
        }
        if tool == .select {
            if let mark = hitTesting.mark(at: point, in: marks) {
                selectedID = mark.id
                gesture = .move(mark, start: point)
            } else {
                selectedID = nil
                gesture = nil
            }
            return
        }
        gesture = .draw(tool, start: point)
    }

    public func pointerDragged(to point: PixelPoint) {
        switch gesture {
        case let .draw(tool, start):
            draft = drawingDraft(tool, from: start, to: point)
        case let .move(mark, start):
            draft = EditorDraft(mark.offset(dx: point.x - start.x, dy: point.y - start.y))
        case let .resize(mark, handle):
            draft = EditorDraft(mark.resized(handle, to: point))
        case nil:
            break
        }
    }

    public func pointerUp(at point: PixelPoint) {
        defer {
            gesture = nil
            draft = nil
        }
        switch gesture {
        case let .draw(tool, start):
            let mark = isClick(start, point) ? click(tool, at: point) : drag(tool, from: start, to: point)
            if let mark { add(mark) }
        case let .move(mark, start):
            guard !isClick(start, point) else { return }
            var moved = mark.offset(dx: point.x - start.x, dy: point.y - start.y)
            moved.targetID = nil
            replace(moved)
        case let .resize(mark, handle):
            replace(mark.resized(handle, to: point))
        case nil:
            break
        }
    }

    func isClick(_ start: PixelPoint, _ end: PixelPoint) -> Bool {
        abs(end.x - start.x) < tolerance && abs(end.y - start.y) < tolerance
    }

    func add(_ mark: Mark) {
        transact { $0.append(mark) }
        selectedID = mark.id
        if mark.kind == .text { editingTextID = mark.id }
    }

    func replace(_ mark: Mark) {
        transact { marks in
            if let index = marks.firstIndex(where: { $0.id == mark.id }) { marks[index] = mark }
        }
        selectedID = mark.id
    }

    // MARK: - Gestures to marks

    func drawingDraft(_ tool: EditorTool, from start: PixelPoint, to end: PixelPoint) -> EditorDraft? {
        guard let kind = tool.markKind else { return nil }
        switch kind {
        case .arrow:
            return EditorDraft(kind: .arrow, geometry: .line(from: start, to: end), color: color(for: .arrow))
        case .circle, .blur, .highlight, .box:
            return EditorDraft(kind: kind, geometry: .rect(PixelRect(corner: start, end)), color: color(for: kind))
        case .text, .step:
            return nil
        }
    }

    /// A click: snap to the target under the pointer, or place a label or step there.
    func click(_ tool: EditorTool, at point: PixelPoint) -> Mark? {
        switch tool {
        case .select:
            return nil
        case .text:
            return Mark(kind: .text, geometry: .rect(PixelRect(x: point.x, y: point.y, width: 0, height: 0)),
                        style: MarkStyle(color: color(for: .text), label: ""))
        case .step:
            return Mark.step(nextStepNumber, at: point, color: color(for: .step))
        case .arrow, .circle, .blur, .highlight, .box:
            guard targetsLoaded else {
                notice = EditorStatus.readingText.text
                return nil
            }
            guard let target = snapping.target(at: point) else {
                notice = "No text here. Drag to draw."
                return nil
            }
            return snapped(tool, to: target)
        }
    }

    func snapped(_ tool: EditorTool, to target: Target) -> Mark? {
        let box = snapping.box(of: target)
        switch tool {
        case .blur:
            // The detector's whole box, never the tighter word union: a redaction over-covers rather than under.
            return .blur(target.rect.standardized, targetID: target.id)
        case .highlight:
            return .highlight(box, color: color(for: .highlight), targetID: target.id)
        case .circle:
            return .circle(box, color: color(for: .circle), targetID: target.id)
        case .box:
            return .box(box, color: color(for: .box), targetID: target.id)
        case .arrow:
            let placement = Placement(imageSize: document.size, layout: layout)
            let obstacles = snapping.obstacles + marks.filter { [.circle, .box, .blur, .highlight].contains($0.kind) }
                .map(\.bounds)
            let arrow = placement.arrow(to: box, from: nil, label: nil, obstacles: obstacles)
            return Mark(kind: .arrow, geometry: .line(from: arrow.from, to: arrow.to), targetID: target.id,
                        style: MarkStyle(color: color(for: .arrow)))
        case .select, .text, .step:
            return nil
        }
    }

    /// A drag: draw what was dragged. An arrow's head snaps to the target under it.
    func drag(_ tool: EditorTool, from start: PixelPoint, to end: PixelPoint) -> Mark? {
        let rect = PixelRect(corner: start, end)
        switch tool {
        case .select:
            return nil
        case .blur:
            return .blur(rect)
        case .highlight:
            return .highlight(rect, color: color(for: .highlight))
        case .circle:
            return .circle(rect, color: color(for: .circle))
        case .box:
            return .box(rect, color: color(for: .box))
        case .text, .step:
            return click(tool, at: tool == .text ? start : end)
        case .arrow:
            if targetsLoaded, let target = snapping.target(at: end) {
                let placement = Placement(imageSize: document.size, layout: layout)
                let arrow = placement.arrow(to: snapping.box(of: target), from: start, label: nil, obstacles: [])
                return Mark(kind: .arrow, geometry: .line(from: arrow.from, to: arrow.to), targetID: target.id,
                            style: MarkStyle(color: color(for: .arrow)))
            }
            return .arrow(from: start, to: end, color: color(for: .arrow))
        }
    }
}
