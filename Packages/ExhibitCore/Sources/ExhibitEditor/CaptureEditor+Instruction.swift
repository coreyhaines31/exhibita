import CoreGraphics
import ExhibitCore
import ExhibitInterpret
import ExhibitPlanning
import Foundation

/// What applying one interpretation did to the capture.
public enum InstructionResult: Equatable, Sendable {
    /// Every part was found and marked. `summary` names each mark.
    case applied(summary: String, marks: Int)
    /// Some parts were marked and some were not found: "Blurred 4 emails. Couldn't find: pricing button."
    case partial(summary: String, marks: Int)
    /// Nothing named was on the screen: "Couldn't find: avatar." Nothing changed.
    case nothingFound(summary: String)
    /// The interpretation had nothing to do and named nothing missing. Nothing changed.
    case nothingToDo
    /// Planning failed (an operation matched none of its targets). Nothing changed.
    case failed(String)

    public var changedMarks: Bool {
        switch self {
        case .applied, .partial: true
        default: false
        }
    }
}

extension CaptureEditor {
    /// Applies an interpretation as one undo step, through the same planning as `exhibit say`, so the marks are
    /// the ones the CLI would write for this capture and these targets. Marks exist before this returns
    /// `applied`; nothing is reported done that was not.
    public func apply(_ interpretation: Interpretation, original: CGImage) -> InstructionResult {
        commitText()
        let canvas = MarkingCanvas(original: original, targets: document.targets, layout: layout, existingMarks: marks)
        let result: InterpretationMarks.Result
        do {
            result = try InterpretationMarks.plan(interpretation, on: canvas)
        } catch let error as PlanError {
            return .failed(error.message)
        } catch {
            return .failed(error.localizedDescription)
        }
        let added = result.marks
        guard !added.isEmpty else {
            return interpretation.notFound.isEmpty ? .nothingToDo : .nothingFound(summary: result.summary.sentence)
        }
        transact { $0 += added }
        selectedID = nil
        return interpretation.notFound.isEmpty
            ? .applied(summary: result.summary.sentence, marks: added.count)
            : .partial(summary: result.summary.sentence, marks: added.count)
    }
}
