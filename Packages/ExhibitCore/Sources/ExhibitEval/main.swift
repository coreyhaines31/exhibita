import ExhibitInterpret
import Foundation

// The interpreter and speech spike (issue 3). Not shipped.
//
//   swift run exhibit-eval interpret [--split dev|heldout|all] [--only grammar,apple,ollama]
//                                    [--ollama-model qwen3.8:27b]
//   swift run exhibit-eval speech
//
// Results go to eval/interpreter/results/. Progress goes to stderr.

struct Options {
    var command = "interpret"
    var split = "dev"
    var only: Set<String> = ["grammar", "apple", "ollama"]
    var ollamaModel = "qwen3.8:27b"

    init(_ arguments: [String]) throws {
        var arguments = arguments[...]
        if let first = arguments.first, !first.hasPrefix("--") { command = first; arguments = arguments.dropFirst() }
        while let argument = arguments.popFirst() {
            switch argument {
            case "--split": split = arguments.popFirst() ?? split
            case "--only": only = Set((arguments.popFirst() ?? "").split(separator: ",").map(String.init))
            case "--ollama-model": ollamaModel = arguments.popFirst() ?? ollamaModel
            default: throw EvalError("unknown argument \(argument)")
            }
        }
        guard ["dev", "heldout", "all"].contains(split) else { throw EvalError("--split is dev, heldout or all") }
    }
}

func runInterpreters(_ options: Options) async throws {
    let set = try EvalSet.load()
    let runner = Runner(set: set, split: options.split)
    var runs: [(name: String, results: [Scored])] = []
    var notes: [String] = []
    var grammar: [Scored]?
    if options.only.contains("grammar") {
        let results = await runner.run(GrammarInterpreter())
        grammar = results
        runs.append(("A grammar", results))
    }
    if options.only.contains("apple") {
        if let results = try await runApple(runner) {
            runs.append(("B Apple on-device", results))
            if let grammar { runs.append(("A then B", Runner.chain(grammar: grammar, model: results))) }
        } else {
            notes.append("B Apple on-device: not assessed, \(appleModelUnavailableReason() ?? "unknown")")
        }
    }
    if options.only.contains("ollama") {
        let model = ModelInterpreter(endpoint: try ModelEndpoint(model: options.ollamaModel, timeout: 300))
        _ = try await model.interpret(InterpretRequest(instruction: "circle ok", targets: []))
        let results = await runner.run(model)
        runs.append(("C ollama:\(options.ollamaModel)", results))
        if let grammar { runs.append(("A then C", Runner.chain(grammar: grammar, model: results))) }
    }
    for run in runs { try Runner.write(run.results, name: run.name.replacingOccurrences(of: " ", with: "_"),
                                       split: options.split) }
    var summary = ["Run on \(osVersion()), split \(options.split), \(runner.selected.count) instructions.", ""]
    let splits = options.split == "all" ? ["heldout", "dev", "all"] : [options.split]
    for split in splits {
        summary += ["### \(split)", "", Report.table(runs, split: split), ""]
    }
    summary += notes
    let text = summary.joined(separator: "\n")
    print(text)
    try Data((text + "\n").utf8).write(to: EvalSet.root.appendingPathComponent("results/summary-\(options.split).md"))
}

func runApple(_ runner: Runner) async throws -> [Scored]? {
    #if canImport(FoundationModels)
    guard #available(macOS 26.0, *), appleModelUnavailableReason() == nil else { return nil }
    let apple = AppleModelInterpreter()
    try await apple.warmUp()
    return await runner.run(apple)
    #else
    return nil
    #endif
}

do {
    let options = try Options(Array(CommandLine.arguments.dropFirst()))
    switch options.command {
    case "interpret": try await runInterpreters(options)
    case "speech": try await runSpeech()
    default: throw EvalError("unknown command \(options.command); use interpret or speech")
    }
} catch {
    log("exhibit-eval: \(error)")
    exit(1)
}
