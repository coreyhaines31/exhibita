import CoreGraphics
import ExhibitCore
import ExhibitInterpret
import Foundation

/// What marks are planned on: a capture's original, its targets, its layout and the marks it already has, which
/// new labels and discs keep clear of.
public struct MarkingCanvas: @unchecked Sendable {
    public var original: CGImage
    public var targets: [Target]
    public var layout: MarkLayout
    public var existingMarks: [Mark]

    public init(original: CGImage, targets: [Target], layout: MarkLayout, existingMarks: [Mark] = []) {
        self.original = original
        self.targets = targets
        self.layout = layout
        self.existingMarks = existingMarks
    }

    public var imageSize: PixelSize { PixelSize(width: original.width, height: original.height) }
}

/// An interpretation, as marks. `exhibit say` and dictation in the editor both come through here, so the same
/// instruction on the same capture and targets gives the same marks and the same summary.
public enum InterpretationMarks {
    /// What one interpretation became: the marks, how each selector did, and the sentence a person reads.
    public struct Result: Sendable {
        public var placed: [PlacedMark]
        public var reports: [SelectorReport]
        public var summary: SaySummary

        public var marks: [Mark] { placed.map(\.mark) }
    }

    /// Plans every operation on `canvas`. Throws `PlanError` when an operation matches nothing at all; an
    /// interpretation with no operations gives no marks.
    public static func plan(_ interpretation: Interpretation, on canvas: MarkingCanvas) throws -> Result {
        let (placed, reports) = try plan(specs(for: interpretation), on: canvas, indexed: true)
        return Result(placed: placed, reports: reports,
                      summary: SaySummary(interpretation: interpretation, targets: canvas.targets))
    }

    /// Every spec as placed marks, in one planner so later marks avoid earlier ones. Throws on the first spec that
    /// fails. `indexed` numbers entries, as `marks.json` does.
    public static func plan(_ specs: [MarkSpec], on canvas: MarkingCanvas, indexed: Bool) throws
        -> (placed: [PlacedMark], reports: [SelectorReport]) {
        let clutter = specs.contains { [.arrow, .text, .step].contains($0.kind) }
            ? Clutter(image: canvas.original, cell: 4 * canvas.layout.unit) : nil
        var planner = Planner(targets: canvas.targets, imageSize: canvas.imageSize, layout: canvas.layout,
                              clutter: clutter, existingMarks: canvas.existingMarks)
        var placed: [PlacedMark] = []
        var reports: [SelectorReport] = []
        for (index, spec) in specs.enumerated() {
            let result = try planner.plan(spec, entry: indexed ? index : nil)
            placed += result.marks
            reports += result.reports
        }
        return (placed, reports)
    }

    /// One spec per operation, naming targets by id so marks stay attached to them in a bundle (a phrase inside a
    /// line by the line's id and the phrase's range, so the mark goes on the phrase). Steps get one spec
    /// per target, so they are numbered in the order said rather than in reading order.
    public static func specs(for interpretation: Interpretation) -> [MarkSpec] {
        interpretation.operations.flatMap { operation -> [MarkSpec] in
            let selectors = operation.picks.map { pick -> MarkSelector in
                switch pick {
                case .id(let id): .target(id)
                case .part(let id, let start, let length): .targetPart(id, NSRange(location: start, length: length))
                case .kind(let kind): .kind(kind)
                case .text(let text): .text(text)
                }
            }
            var spec = MarkSpec(kind: operation.mark)
            spec.label = operation.label
            spec.all = true
            spec.allowMissing = true
            if operation.mark == .step {
                return selectors.map { selector in
                    var single = spec
                    single.selectors = [selector]
                    return single
                }
            }
            spec.selectors = selectors
            return [spec]
        }
    }
}
