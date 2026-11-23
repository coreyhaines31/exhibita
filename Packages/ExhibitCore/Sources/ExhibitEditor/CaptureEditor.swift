import ExhibitCore
import ExhibitShell
import Foundation
import Observation

/// The editor's brain for one open capture: the tool, the colour, the selection, gestures in image pixels,
/// keys, undo and redo. Every mark change goes through `transact`, which records one undo step and hands the
/// marks to the document's owner to save. The app forwards pointer events and keys, and draws what this says.
@MainActor
@Observable
public final class CaptureEditor {
    public let owner: DocumentOwner
    public let layout: MarkLayout
    public private(set) var tool: EditorTool = .select
    /// The colour picked with 1 to 4; until then each kind uses its default (red, yellow for highlight).
    public private(set) var chosenColor: MarkColor?
    public internal(set) var selectedID: UUID?
    /// The text label being typed into, if any.
    public internal(set) var editingTextID: UUID?
    /// The shape being dragged, drawn as an outline until the pointer comes up.
    public internal(set) var draft: EditorDraft?
    /// A message from the last action: "Copied", "Reading text", "No text here".
    public internal(set) var notice: String?
    /// Where dictation or a typed instruction is: listening, working, or what it did. Set by `DictationSession`;
    /// a finished one goes away on the next action, like a notice.
    public internal(set) var dictation: DictationStatus?
    /// Where the pointer is over the capture, in image pixels, for "highlight this". The app sets it on hover.
    @ObservationIgnored public var hoverPoint: PixelPoint?
    /// The keys in effect: the defaults with whatever the person changed in Settings. The app keeps it current.
    public var keymap: EditorKeymap = .standard
    /// How far from a thing a click still counts, and how far the pointer must move to be a drag, in image
    /// pixels. The app sets it from the zoom so it is about 4 points on screen.
    public var tolerance: Double

    @ObservationIgnored private var undoStack: [[Mark]] = []
    @ObservationIgnored private var redoStack: [[Mark]] = []
    @ObservationIgnored var gesture: EditorGesture?
    /// Undo steps kept.
    public static let undoLimit = 200

    public init(owner: DocumentOwner, tolerance: Double? = nil) {
        self.owner = owner
        layout = MarkLayout(scale: owner.document.scale, imageSize: owner.document.size)
        self.tolerance = tolerance ?? 4 * owner.document.scale
        owner.onMarksAdded = { [weak self] added in self?.keepInHistory(added) }
    }

    /// Marks added outside the editor (an agent capture's auto-blur) join every undo and redo step, so undoing
    /// the person's own change never takes them away. The person can still delete them.
    private func keepInHistory(_ added: [Mark]) {
        undoStack = undoStack.map { $0 + added }
        redoStack = redoStack.map { $0 + added }
    }

    // MARK: - What the views read

    public var document: CaptureDocument { owner.document }
    public var marks: [Mark] { owner.document.marks }
    public var targetsLoaded: Bool { owner.targetsLoaded }
    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }
    public var selectedMark: Mark? { selectedID.flatMap { id in marks.first { $0.id == id } } }

    /// The colour the current tool draws in.
    public var currentColor: MarkColor { color(for: tool.markKind ?? .arrow) }

    public func color(for kind: MarkKind) -> MarkColor {
        chosenColor ?? (kind == .highlight ? .yellow : .red)
    }

    public var status: EditorStatus {
        if let notice { return .notice(notice) }
        if let dictation { return .dictation(dictation) }
        if !targetsLoaded { return .readingText }
        let secrets = uncoveredSecrets
        return secrets.isEmpty ? .none : .secrets(secrets.count)
    }

    /// Detected secrets no blur covers yet.
    public var uncoveredSecrets: [Target] {
        let blurs = marks.filter { $0.kind == .blur }
        return Snapping.sensitive(document.targets).filter { target in
            !blurs.contains { $0.targetID == target.id || $0.bounds.covers(target.rect.standardized) }
        }
    }

    public var nextStepNumber: Int {
        (marks.filter { $0.kind == .step }.map { $0.style.stepNumber ?? 1 }.max() ?? 0) + 1
    }

    var snapping: Snapping { Snapping(targets: document.targets, slack: tolerance) }
    var hitTesting: MarkHitTesting { MarkHitTesting(layout: layout, tolerance: tolerance) }

    /// The handles of the selected mark, for drawing.
    public var selectedHandles: [PixelPoint] {
        selectedMark.map { hitTesting.handles(of: $0).map(\.1) } ?? []
    }

    /// What a person sees of `mark`: a label's backing, a step's disc, a circle's padded box.
    public func visibleBox(of mark: Mark) -> PixelRect {
        hitTesting.visibleBox(of: mark)
    }

    /// The label being typed into, for drawing a caret after it.
    public var editingMark: Mark? {
        editingTextID.flatMap { id in marks.first { $0.id == id } }
    }

    /// The box the selected mark's ink reaches, for drawing a selection outline outside it.
    public var selectionBox: PixelRect? {
        selectedMark.map { layout.inkBox(of: $0) }
    }

    // MARK: - Changes and undo

    /// Applies `change` to the marks as one undo step and saves. Several marks changed at once (⇧B, a dictated
    /// batch) are still one step. Returns whether anything changed.
    @discardableResult
    public func transact(_ change: (inout [Mark]) -> Void) -> Bool {
        let before = marks
        var after = before
        change(&after)
        guard after != before else { return false }
        undoStack.append(before)
        if undoStack.count > Self.undoLimit { undoStack.removeFirst(undoStack.count - Self.undoLimit) }
        redoStack.removeAll()
        owner.setMarks(after)
        return true
    }

    public func undo() {
        commitText()
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(marks)
        owner.setMarks(previous)
        dropStaleSelection()
    }

    public func redo() {
        commitText()
        guard let next = redoStack.popLast() else { return }
        undoStack.append(marks)
        owner.setMarks(next)
        dropStaleSelection()
    }

    private func dropStaleSelection() {
        if let selectedID, !marks.contains(where: { $0.id == selectedID }) { self.selectedID = nil }
    }

    // MARK: - Commands

    public func choose(_ tool: EditorTool) {
        commitText()
        self.tool = tool
        if tool != .select { selectedID = nil }
    }

    /// Sets the colour for new marks, and recolours the selected mark (one undo step).
    public func choose(_ color: MarkColor) {
        commitText()
        chosenColor = color
        guard let selected = selectedMark, selected.kind != .blur else { return }
        transact { marks in
            if let index = marks.firstIndex(where: { $0.id == selected.id }) { marks[index].style.color = color }
        }
    }

    /// ⇧B. Blurs every detected secret no blur covers yet, as one undo step. Returns how many.
    @discardableResult
    public func blurAllSensitive() -> Int {
        commitText()
        guard targetsLoaded else {
            notice = EditorStatus.readingText.text
            return 0
        }
        let secrets = uncoveredSecrets
        guard !secrets.isEmpty else {
            notice = "No secrets to blur"
            return 0
        }
        transact { marks in
            marks += secrets.map { Mark.blur($0.rect.standardized, targetID: $0.id) }
        }
        notice = secrets.count == 1 ? "Blurred 1 possible secret" : "Blurred \(secrets.count) possible secrets"
        return secrets.count
    }

    public func deleteSelection() {
        guard let selectedID else { return }
        transact { $0.removeAll { $0.id == selectedID } }
        self.selectedID = nil
    }

    /// Shows a message in the status line until the next action.
    public func show(_ message: String) {
        notice = message
        clearFinishedDictation()
    }

    /// Drops what the last instruction did from the status line; one still in progress stays.
    func clearFinishedDictation() {
        if dictation?.isLive == false { dictation = nil }
    }

    /// Runs a command the editor handles itself.
    public func perform(_ command: EditorCommand) {
        switch command {
        case .tool(let tool): choose(tool)
        case .color(let color): choose(color)
        case .blurAllSensitive: blurAllSensitive()
        case .undo: undo()
        case .redo: redo()
        case .deleteSelection: deleteSelection()
        case .copy, .copyAndClose, .copyAndDelete, .save, .copyPath, .close, .dictate, .typeInstruction: commitText()
        }
    }

    // MARK: - Keys

    /// A key press. While a label is being typed, characters go into it and ↩ or Esc finish it.
    public func handle(_ key: EditorKey, modifiers: KeyModifiers = []) -> EditorKeyResult {
        let modifiers = modifiers.intersection(.all)
        if editingTextID != nil {
            switch key {
            case .returnKey, .escape:
                // ⇧↩ as well: a habit from typing line breaks must finish the label, never copy and delete.
                if modifiers.isSubset(of: [.shift]) {
                    commitText()
                    return .handled
                }
            case .delete:
                if modifiers.isEmpty {
                    editLabel { $0 = String($0.dropLast()) }
                    return .handled
                }
            case .character(let typed):
                if modifiers.isSubset(of: [.shift]) {
                    editLabel { $0 += typed }
                    return .handled
                }
            }
            commitText()
        }
        guard let command = keymap.command(for: key, modifiers: modifiers) else { return .ignored }
        notice = nil
        clearFinishedDictation()
        if command.isAppCommand {
            commitText()
            return .app(command)
        }
        perform(command)
        return .handled
    }

    // MARK: - Text labels

    private func editLabel(_ change: (inout String) -> Void) {
        guard let editingTextID, let index = marks.firstIndex(where: { $0.id == editingTextID }) else { return }
        var updated = marks
        var label = updated[index].style.label ?? ""
        change(&label)
        updated[index].style.label = label
        // Typing is part of the step that placed the label, so it saves without a new undo step.
        owner.setMarks(updated)
    }

    /// Finishes typing. A label left empty is removed along with the step that placed it.
    public func commitText() {
        guard let editingTextID else { return }
        self.editingTextID = nil
        let label = marks.first { $0.id == editingTextID }?.style.label ?? ""
        guard label.isEmpty else { return }
        if let previous = undoStack.popLast() {
            owner.setMarks(previous)
        } else {
            owner.setMarks(marks.filter { $0.id != editingTextID })
        }
        if selectedID == editingTextID { selectedID = nil }
    }
}
