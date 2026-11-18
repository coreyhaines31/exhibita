import ExhibitCore
import Foundation

/// One mark request: a command line, or one entry of `marks.json`.
struct MarkSpec: Equatable {
    var kind: MarkKind
    var selectors: [Selector] = []
    /// Arrow tail, fixed.
    var from: PixelPoint?
    /// Arrow head, fixed. Only from `marks.json`, with `from`, for an arrow drawn by coordinates alone.
    var toPoint: PixelPoint?
    var label: String?
    var color: MarkColor?
    var number: Int?
    var all = false
    var nth: Int?
    var allowMissing = false

    var needsTargets: Bool {
        selectors.contains(where: \.needsTargets) || [.arrow, .text, .step].contains(kind)
    }

    /// Blur and highlight cover every match; the rest draw one mark per selector unless told otherwise.
    var coversEveryMatch: Bool { kind == .blur || kind == .highlight }

    func validate() throws {
        if kind == .arrow, toPoint != nil {
            guard from != nil else { throw CLIError.usage("An arrow with a \"to\" point also needs \"from\".") }
            guard selectors.isEmpty else {
                throw CLIError.usage("An arrow with a \"to\" point takes no selectors; use one or the other.")
            }
            return
        }
        guard !selectors.isEmpty else {
            throw CLIError.usage("Say what to \(kind.rawValue): give --text, --to, --regex, --kind or --rect.")
        }
        try validateOptions()
    }

    private func validateOptions() throws {
        if from != nil, kind != .arrow { throw CLIError.usage("--from only applies to arrow.") }
        if label != nil, kind != .arrow, kind != .text { throw CLIError.usage("--label only applies to arrow and text.") }
        if kind == .text, (label ?? "").isEmpty { throw CLIError.usage("text needs --label with the words to show.") }
        if number != nil, kind != .step { throw CLIError.usage("--number only applies to step.") }
        if let number, number < 0 { throw CLIError.usage("--number must be 0 or more.") }
        if all, nth != nil { throw CLIError.usage("Use --all or --nth, not both.") }
        if let nth, nth < 1 { throw CLIError.usage("--nth counts from 1.") }
    }
}

/// A mark ready to save or render, with what produced it.
struct PlacedMark {
    var mark: Mark
    var selector: String?
    var entry: Int?
    /// The box a person sees: a text label, a step disc, an arrow's caption.
    var visibleBox: PixelRect?
}

/// How many things one selector matched and how many marks it produced.
struct SelectorReport: Encodable, Equatable {
    var entry: Int?
    var selector: String
    var matches: Int
    var marked: Int
}

/// Turns specs into marks. Keeps state across specs, so a batch avoids its own labels and numbers steps on.
struct Planner {
    let targets: [Target]
    let placement: Placement
    private(set) var obstacles: [PixelRect]
    private var nextStep = 1

    init(targets: [Target], imageSize: PixelSize, layout: MarkLayout, clutter: Clutter? = nil,
         existingMarks: [Mark] = []) {
        self.targets = targets
        placement = Placement(imageSize: imageSize, layout: layout, clutter: clutter)
        // Words rather than whole lines, so a mark may sit beside its target on the same line.
        obstacles = targets.flatMap { target -> [PixelRect] in
            if target.kind == .text, let spans = target.spans, !spans.isEmpty { return spans.map(\.rect.standardized) }
            return [target.rect.standardized]
        }
        obstacles += existingMarks.compactMap(Self.footprint(of:))
    }

    mutating func plan(_ spec: MarkSpec, entry: Int? = nil) throws -> (marks: [PlacedMark], reports: [SelectorReport]) {
        do {
            return try planUnlabelled(spec, entry: entry)
        } catch let error as CLIError {
            throw error.inEntry(entry)
        }
    }

    private mutating func planUnlabelled(_ spec: MarkSpec, entry: Int?) throws
        -> (marks: [PlacedMark], reports: [SelectorReport]) {
        try spec.validate()
        if spec.kind == .arrow, let from = spec.from, let to = spec.toPoint {
            let mark = Mark(kind: .arrow, geometry: .line(from: from, to: to),
                            style: MarkStyle(color: spec.color ?? .red, label: spec.label))
            let caption = spec.label.flatMap { placement.layout.captionRect(from: from, to: to, label: $0) }
            caption.map { obstacles.append($0) }
            return ([PlacedMark(mark: mark, entry: entry, visibleBox: caption)], [])
        }

        let resolved = try spec.selectors.map { ($0, try SelectorMatcher.candidates(for: $0, in: targets)) }
        let missing = resolved.filter { $0.1.isEmpty }.map(\.0)
        if !missing.isEmpty, !spec.allowMissing || missing.count == resolved.count {
            let names = missing.map(\.description)
            var error = CLIError(code: "no_match", message: "No match for " + names.joined(separator: ", ") + ".",
                                 status: .noMatch, selectors: names)
            error.hint = missing.compactMap(SelectorMatcher.hint(for:)).first
            throw error
        }

        var picks: [(selector: Selector, candidate: Candidate)] = []
        var reports: [SelectorReport] = []
        for (selector, candidates) in resolved {
            let chosen = try pick(from: candidates, selector: selector, spec: spec)
            var marked = 0
            for candidate in chosen where !picks.contains(where: { $0.candidate.rect == candidate.rect }) {
                picks.append((selector, candidate))
                marked += 1
            }
            reports.append(SelectorReport(entry: entry, selector: selector.description, matches: candidates.count,
                                          marked: marked))
        }
        if spec.kind == .step {
            picks.sort { lhs, rhs in
                (lhs.candidate.rect.minY, lhs.candidate.rect.minX) < (rhs.candidate.rect.minY, rhs.candidate.rect.minX)
            }
        }
        var number = spec.number ?? nextStep
        var marks: [PlacedMark] = []
        for (selector, candidate) in picks {
            var placed = place(spec, on: candidate, stepNumber: number)
            placed.selector = selector.description
            placed.entry = entry
            if spec.kind == .step { number += 1 }
            if let box = placed.visibleBox ?? Self.footprint(of: placed.mark) { obstacles.append(box) }
            marks.append(placed)
        }
        if spec.kind == .step { nextStep = number }
        return (marks, reports)
    }

    /// The area a placed mark covers, for later placements to avoid. Arrows without a caption are left out: their
    /// bounding box is mostly empty.
    static func footprint(of mark: Mark) -> PixelRect? {
        mark.kind == .arrow || mark.kind == .text || mark.kind == .step ? nil : mark.bounds
    }

    private func pick(from candidates: [Candidate], selector: Selector, spec: MarkSpec) throws -> [Candidate] {
        if let nth = spec.nth {
            if candidates.isEmpty { return [] }
            guard nth <= candidates.count else {
                throw CLIError(code: "nth_out_of_range",
                               message: "\(selector.description) matched \(candidates.count), so there is no --nth \(nth).",
                               status: .noMatch, selectors: [selector.description],
                               candidates: candidates.map(\.report))
            }
            return [candidates[nth - 1]]
        }
        if spec.all || spec.coversEveryMatch || candidates.count <= 1 { return candidates }
        throw CLIError(code: "ambiguous",
                       message: "\(selector.description) matched \(candidates.count) things and \(spec.kind.rawValue) "
                           + "draws one. Pass --all for every match, or --nth <n> to pick one (counting from 1).",
                       status: .ambiguous, selectors: [selector.description], candidates: candidates.map(\.report))
    }

    private func place(_ spec: MarkSpec, on candidate: Candidate, stepNumber: Int) -> PlacedMark {
        let rect = candidate.rect
        let id = candidate.targetID
        switch spec.kind {
        case .blur:
            return PlacedMark(mark: .blur(rect, targetID: id))
        case .highlight:
            return PlacedMark(mark: .highlight(rect, color: spec.color ?? .yellow, targetID: id))
        case .circle:
            return PlacedMark(mark: .circle(rect, color: spec.color ?? .red, targetID: id))
        case .box:
            return PlacedMark(mark: .box(rect, color: spec.color ?? .red, targetID: id))
        case .text:
            let label = spec.label ?? ""
            let box = placement.label(size: placement.layout.labelSize(label), beside: rect, obstacles: obstacles)
            let mark = Mark(kind: .text, geometry: .rect(PixelRect(x: box.x, y: box.y, width: 0, height: 0)),
                            targetID: id, style: MarkStyle(color: spec.color ?? .red, label: label))
            return PlacedMark(mark: mark, visibleBox: box)
        case .step:
            let center = placement.step(beside: rect, obstacles: obstacles)
            let diameter = placement.layout.stepDiameter
            let mark = Mark(kind: .step, geometry: .rect(PixelRect(x: center.x, y: center.y, width: 0, height: 0)),
                            targetID: id, style: MarkStyle(color: spec.color ?? .red, stepNumber: stepNumber))
            return PlacedMark(mark: mark, visibleBox: PixelRect(x: center.x - diameter / 2, y: center.y - diameter / 2,
                                                                width: diameter, height: diameter))
        case .arrow:
            let arrow = placement.arrow(to: rect, from: spec.from, label: spec.label, obstacles: obstacles)
            let mark = Mark(kind: .arrow, geometry: .line(from: arrow.from, to: arrow.to), targetID: id,
                            style: MarkStyle(color: spec.color ?? .red, label: spec.label))
            return PlacedMark(mark: mark, visibleBox: arrow.caption)
        }
    }
}
