import ExhibitCore

/// What a pointer gesture does. Each drawing tool makes one mark kind; select moves, resizes and deletes marks.
public enum EditorTool: String, CaseIterable, Sendable {
    case select
    case arrow
    case circle
    case blur
    case highlight
    case text
    case box
    case step

    /// The tools in the order the toolbar shows them, with select last.
    public static let toolbarOrder: [EditorTool] = [.arrow, .circle, .blur, .highlight, .text, .box, .step, .select]

    /// The single key that picks the tool. The keys are the interface; the toolbar only teaches them.
    public var key: String {
        switch self {
        case .select: "V"
        case .arrow: "A"
        case .circle: "C"
        case .blur: "B"
        case .highlight: "H"
        case .text: "T"
        case .box: "R"
        case .step: "N"
        }
    }

    public var title: String {
        switch self {
        case .select: "Select"
        case .arrow: "Arrow"
        case .circle: "Circle"
        case .blur: "Blur"
        case .highlight: "Highlight"
        case .text: "Text"
        case .box: "Box"
        case .step: "Step"
        }
    }

    /// The mark a drawing tool makes; nil for select.
    public var markKind: MarkKind? {
        switch self {
        case .select: nil
        case .arrow: .arrow
        case .circle: .circle
        case .blur: .blur
        case .highlight: .highlight
        case .text: .text
        case .box: .box
        case .step: .step
        }
    }

    /// Whether a click (rather than a drag) snaps the mark to the text or target under the pointer.
    public var snapsOnClick: Bool {
        [.arrow, .circle, .blur, .highlight, .box].contains(self)
    }
}

extension MarkColor {
    /// The colour key, 1 to 4.
    public var key: String {
        switch self {
        case .red: "1"
        case .yellow: "2"
        case .blue: "3"
        case .green: "4"
        }
    }

    public var title: String {
        switch self {
        case .red: "Red"
        case .yellow: "Yellow"
        case .blue: "Blue"
        case .green: "Green"
        }
    }
}
