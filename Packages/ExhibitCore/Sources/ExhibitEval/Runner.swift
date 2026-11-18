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
            let milliseconds = Self.milliseconds(clock.now - start)
            var scored = Scoring.score(instruction, outcome: outcome, targets: request.targets,
                                       milliseconds: milliseconds)
            scored.answeredBy = scored.answered ? interpreter.name : nil
            log("\(interpreter.name) \(index + 1)/\(selected.count) \(instruction.id) "
                + "\(scored.exact ? "ok" : scored.answered ? "WRONG" : "declined") "
                + "\(Int(milliseconds)) ms: \(scored.output)")
            results.append(scored)
        }
        return results
    }

    /// What ships: the grammar's answers where it answered, and the model asked only where the grammar declined,
    /// as `exhibit say` does. The model step is timed on its own as well.
    func runChain(grammar: [Scored], model: ModelInterpreter) async -> [Scored] {
        var results: [Scored] = []
        let declined = grammar.filter { !$0.answered }.count
        var asked = 0
        for (instruction, first) in zip(selected, grammar) {
            guard !first.answered else {
                results.append(first)
                continue
            }
            asked += 1
            let request = set.request(for: instruction)
            let clock = ContinuousClock()
            let start = clock.now
            let outcome: Result<InterpretOutcome, Error>
            var timings: ModelTimings?
            do {
                let answer = try await model.interpretWithTimings(request)
                outcome = .success(answer.outcome)
                timings = answer.timings
            } catch {
                outcome = .failure(error)
            }
            let milliseconds = Self.milliseconds(clock.now - start)
            var scored = Scoring.score(instruction, outcome: outcome, targets: request.targets,
                                       milliseconds: first.milliseconds + milliseconds)
            scored.answeredBy = scored.answered ? "model" : nil
            scored.modelMilliseconds = milliseconds
            scored.modelTimings = timings
            log("grammar then model \(asked)/\(declined) \(instruction.id) "
                + "\(scored.exact ? "ok" : scored.answered ? "WRONG" : "failed") \(Int(milliseconds)) ms"
                + "\(timings.map { " (\(Report.timings($0)))" } ?? ""): \(scored.output)")
            results.append(scored)
        }
        return results
    }

    static func milliseconds(_ elapsed: Duration) -> Double {
        Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15
    }

    /// The grammar first, the model only where the grammar declined, computed from two recorded runs (for Apple's
    /// model, which is not shipped).
    static func chain(grammar: [Scored], model: [Scored]) -> [Scored] {
        zip(grammar, model).map { first, second in
            guard !first.answered else { return first }
            var combined = second
            combined.modelMilliseconds = second.milliseconds
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
    static let legend = [
        "Missed redaction targets are expected blur targets no blur covers, split into instructions that name a kind, "
            + "a literal string or the pointer, and semantic ones (tagged \"semantic\"). Over-redacted counts blurs "
            + "that touch no expected target. Not found right: of instructions whose answer is \"not on the screen\", "
            + "those reported as not found with nothing marked in their place. Model step: time of the model call "
            + "alone, on the instructions the grammar declined. Missed and over-redacted count answered "
            + "instructions only.",
        ""
    ]

    static func table(_ runs: [(name: String, results: [Scored])], split: String) -> String {
        var lines = [
            "| Interpreter | Answered | Exact, of answered | Exact, of all | Missed redaction, kind or literal | "
                + "Missed redaction, semantic | Over-redacted | Not found right | Median ms | p90 ms | "
                + "Model step median ms | Model step p90 ms |",
            "|---|---|---|---|---|---|---|---|---|---|---|---|"
        ]
        for run in runs {
            let rows = split == "all" ? run.results : run.results.filter { $0.split == split }
            guard !rows.isEmpty else { continue }
            let answered = rows.filter(\.answered)
            let exact = rows.filter(\.exact).count
            let literal = rows.filter { !$0.tags.contains("semantic") && $0.missedRedactions != nil }
            let semantic = rows.filter { $0.tags.contains("semantic") && $0.missedRedactions != nil }
            let over = answered.compactMap(\.overRedactions).reduce(0, +)
            let notFound = rows.compactMap(\.notFoundCorrect)
            let latencies = rows.map(\.milliseconds).sorted()
            let modelSteps = rows.compactMap(\.modelMilliseconds).sorted()
            lines.append("| \(run.name) | \(answered.count)/\(rows.count) | "
                + "\(fraction(exact, answered.count)) | \(fraction(exact, rows.count)) | "
                + "\(missed(literal)) | \(missed(semantic)) | \(over) | "
                + "\(fraction(notFound.filter { $0 }.count, notFound.count)) | "
                + "\(format(percentile(latencies, 0.5))) | \(format(percentile(latencies, 0.9))) | "
                + "\(modelSteps.isEmpty ? "n/a" : format(percentile(modelSteps, 0.5))) | "
                + "\(modelSteps.isEmpty ? "n/a" : format(percentile(modelSteps, 0.9))) |")
        }
        return lines.joined(separator: "\n")
    }

    /// One call's server timings in a short form: "load 0.0 s, prompt 1265 tokens 14.2 s, output 29 tokens 1.6 s".
    static func timings(_ timings: ModelTimings) -> String {
        func seconds(_ value: Double?) -> String { value.map { String(format: "%.1f s", $0) } ?? "?" }
        var parts: [String] = []
        if let load = timings.loadSeconds { parts.append("load \(seconds(load))") }
        if let tokens = timings.promptTokens {
            let cached = timings.cachedPromptTokens.map { ", \($0) cached" } ?? ""
            parts.append("prompt \(tokens) tokens\(cached)" + (timings.promptSeconds.map { " \(seconds($0))" } ?? ""))
        }
        if let tokens = timings.outputTokens {
            parts.append("output \(tokens) tokens" + (timings.outputSeconds.map { " \(seconds($0))" } ?? ""))
        }
        if let thinking = timings.thinkingCharacters, thinking > 0 { parts.append("reasoned \(thinking) characters") }
        return parts.joined(separator: ", ")
    }

    /// One paragraph per run whose model calls reported timings.
    static func breakdowns(_ runs: [(name: String, results: [Scored])], split: String) -> [String] {
        runs.flatMap { run -> [String] in
            let rows = split == "all" ? run.results : run.results.filter { $0.split == split }
            return modelBreakdown(rows).map { ["\(run.name): \($0)", ""] } ?? []
        }
    }

    /// Where the model step's time went, as medians over the calls that reported timings; nil when none did.
    static func modelBreakdown(_ rows: [Scored]) -> String? {
        let timings = rows.compactMap(\.modelTimings)
        guard !timings.isEmpty else { return nil }
        func median(_ values: [Double]) -> String {
            values.isEmpty ? "n/a" : String(format: "%.2f", percentile(values.sorted(), 0.5))
        }
        let reasoned = timings.filter { ($0.thinkingCharacters ?? 0) > 0 }.count
        return "\(timings.count) model calls, medians: load \(median(timings.compactMap(\.loadSeconds))) s, "
            + "prompt \(median(timings.compactMap(\.promptTokens).map(Double.init))) tokens in "
            + "\(median(timings.compactMap(\.promptSeconds))) s, output "
            + "\(median(timings.compactMap(\.outputTokens).map(Double.init))) tokens in "
            + "\(median(timings.compactMap(\.outputSeconds))) s; \(reasoned) reasoned."
    }

    /// Missed targets over the answered instructions, and how many such instructions there were.
    static func missed(_ rows: [Scored]) -> String {
        let answered = rows.filter(\.answered)
        let count = answered.compactMap(\.missedRedactions).reduce(0, +)
        return "\(count) (\(answered.count) of \(rows.count) blur instructions answered)"
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
