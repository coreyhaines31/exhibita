import ExhibitInterpret
import Foundation

/// Runs interpreters over the eval set and writes scored results.
struct Runner {
    let set: EvalSet
    let split: String

    var selected: [EvalInstruction] {
        split == "all" ? set.instructions : set.instructions.filter { $0.split == split }
    }

    func run(_ interpreter: any Interpreter) async -> [Scored] {
        var results: [Scored] = []
        for (index, instruction) in selected.enumerated() {
            let request = set.request(for: instruction)
            let clock = ContinuousClock()
            let start = clock.now
            let outcome: Result<InterpretOutcome, Error>
            do {
                outcome = .success(try await interpreter.interpret(request))
            } catch {
                outcome = .failure(error)
            }
            let elapsed = clock.now - start
            let milliseconds = Double(elapsed.components.seconds) * 1000
                + Double(elapsed.components.attoseconds) / 1e15
            let scored = Scoring.score(instruction, outcome: outcome, targets: request.targets,
                                       milliseconds: milliseconds)
            log("\(interpreter.name) \(index + 1)/\(selected.count) \(instruction.id) "
                + "\(scored.exact ? "ok" : scored.answered ? "WRONG" : "declined") "
                + "\(Int(milliseconds)) ms: \(scored.output)")
            results.append(scored)
        }
        return results
    }

    /// The grammar first, the model only where the grammar declined: what would ship. Computed from the two
    /// recorded runs; the grammar is deterministic and the models decode greedily, so re-running would repeat them.
    static func chain(grammar: [Scored], model: [Scored]) -> [Scored] {
        zip(grammar, model).map { first, second in
            guard !first.answered else { return first }
            var combined = second
            combined.milliseconds += first.milliseconds
            return combined
        }
    }

    static func write(_ results: [Scored], name: String, split: String) throws {
        let directory = EvalSet.root.appendingPathComponent("results")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let safe = name.replacingOccurrences(of: ":", with: "-").replacingOccurrences(of: "/", with: "-")
        try encoder.encode(results).write(to: directory.appendingPathComponent("\(safe)-\(split).json"))
    }
}

func log(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

/// The summary table for one split.
enum Report {
    static func table(_ runs: [(name: String, results: [Scored])], split: String) -> String {
        var lines = [
            "| Interpreter | Answered | Exact, of answered | Exact, of all | Missed redaction targets | "
                + "Over-redacted targets | Median ms | p90 ms |",
            "|---|---|---|---|---|---|---|---|"
        ]
        for run in runs {
            let rows = split == "all" ? run.results : run.results.filter { $0.split == split }
            guard !rows.isEmpty else { continue }
            let answered = rows.filter(\.answered)
            let exact = rows.filter(\.exact).count
            let missed = answered.compactMap(\.missedRedactions).reduce(0, +)
            let over = answered.compactMap(\.overRedactions).reduce(0, +)
            let redactions = rows.filter { $0.missedRedactions != nil || $0.tags.contains("blur") }.count
            let latencies = rows.map(\.milliseconds).sorted()
            lines.append("| \(run.name) | \(answered.count)/\(rows.count) | "
                + "\(fraction(exact, answered.count)) | \(fraction(exact, rows.count)) | "
                + "\(missed) (in \(redactions) blur instructions) | \(over) | "
                + "\(format(percentile(latencies, 0.5))) | \(format(percentile(latencies, 0.9))) |")
        }
        return lines.joined(separator: "\n")
    }

    static func fraction(_ count: Int, _ total: Int) -> String {
        guard total > 0 else { return "n/a" }
        return "\(count)/\(total) (\(Int((Double(count) / Double(total) * 100).rounded()))%)"
    }

    static func percentile(_ sorted: [Double], _ fraction: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let index = Int((Double(sorted.count - 1) * fraction).rounded(.up))
        return sorted[min(index, sorted.count - 1)]
    }

    static func format(_ milliseconds: Double) -> String {
        milliseconds < 10 ? String(format: "%.2f", milliseconds) : String(Int(milliseconds.rounded()))
    }
}
