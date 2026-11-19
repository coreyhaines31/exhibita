import ExhibitCore
import ExhibitInterpret
import Foundation

/// `eval/interpreter`: fixture target lists and the instructions with their expected results.
struct EvalSet {
    var fixtures: [String: [Target]]
    var instructions: [EvalInstruction]

    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("eval/interpreter")

    /// Loads an instructions file: an absolute path, a path from the current directory, or a name in
    /// `eval/interpreter`. Fixtures always come from `eval/interpreter/fixtures`.
    static func load(file: String = "instructions.json") throws -> EvalSet {
        let fromHere = URL(fileURLWithPath: file)
        let url = FileManager.default.fileExists(atPath: fromHere.path) ? fromHere : root.appendingPathComponent(file)
        let file = try JSONDecoder().decode(InstructionsFile.self, from: Data(contentsOf: url))
        var fixtures: [String: [Target]] = [:]
        for name in Set(file.instructions.map(\.fixture)) {
            let url = root.appendingPathComponent("fixtures/\(name).targets.json")
            fixtures[name] = try JSONDecoder().decode(TargetsFile.self, from: Data(contentsOf: url)).targets
        }
        let set = EvalSet(fixtures: fixtures, instructions: file.instructions)
        try set.validate()
        return set
    }

    /// Every matcher in every expectation must name at least one target, so a typo cannot pass as "nothing".
    func validate() throws {
        for instruction in instructions {
            let targets = fixtures[instruction.fixture] ?? []
            for expectation in [instruction.expected] + (instruction.alternatives ?? []) {
                for operation in expectation.operations {
                    for matcher in operation.targets where matcher.resolve(in: targets).isEmpty {
                        throw EvalError("\(instruction.id): \(matcher) matches nothing")
                    }
                }
            }
        }
    }

    func request(for instruction: EvalInstruction) -> InterpretRequest {
        InterpretRequest(instruction: instruction.instruction, targets: fixtures[instruction.fixture] ?? [],
                         pointer: instruction.pointer)
    }
}

struct EvalError: Error, CustomStringConvertible {
    var description: String
    init(_ description: String) { self.description = description }
}

private struct InstructionsFile: Decodable {
    var instructions: [EvalInstruction]
}

private struct TargetsFile: Decodable {
    var targets: [Target]
}

struct EvalInstruction: Decodable {
    var id: String
    var fixture: String
    var split: String
    var tags: [String]
    var instruction: String
    var pointer: PixelPoint?
    var expected: Expectation
    var alternatives: [Expectation]?
}

struct Expectation: Decodable {
    var operations: [ExpectedOperation]
    var notFound: Bool?
}

struct ExpectedOperation: Decodable {
    var mark: MarkKind
    var targets: [Matcher]
    var label: String?
}

/// How an expectation names targets. See `about` in `instructions.json`.
struct Matcher: Decodable, CustomStringConvertible {
    var kind: String?
    var line: String?
    var contains: String?
    var id: String?

    func resolve(in targets: [Target]) -> [Target] {
        if let kind { return targets.filter { $0.kind.rawValue == kind } }
        if let line {
            return targets.filter { $0.kind == .text && $0.text?.lowercased() == line.lowercased() }
        }
        if let contains { return TargetPick.text(contains).targets(in: targets) }
        if let id { return targets.filter { $0.id.uuidString.hasPrefix(id.uppercased()) } }
        return []
    }

    var description: String {
        [kind.map { "kind \($0)" }, line.map { "line \($0)" }, contains.map { "contains \($0)" }, id.map { "id \($0)" }]
            .compactMap { $0 }.joined()
    }
}
