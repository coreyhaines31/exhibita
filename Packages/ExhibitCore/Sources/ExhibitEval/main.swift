import ExhibitInterpret
import Foundation

// The interpreter eval. Not shipped.
//
//   swift run exhibit-eval interpret [--file instructions.json] [--split dev|heldout|all|<any split in the file>]
//                                    [--only grammar,model,apple,model-alone]
//                                    [--model qwen3.8:27b] [--model-endpoint http://127.0.0.1:11434]
//                                    [--warm <seconds>]
//   swift run exhibit-eval speech
//
// "grammar" is the shipping grammar. "model" is the shipping chain, as `exhibit say` runs it: the grammar first, then
// the shipping model interpreter only where the grammar declined. "model-alone" asks the model every instruction.
// --warm sends the editor's warm-up that many seconds before each model instruction (once per screen).
// "apple" is Apple's on-device model (not shipped). Results go to eval/interpreter/results/, named after the split.
// Progress goes to stderr.

struct Options {
    var command = "interpret"
    var file = "instructions.json"
    var split = "dev"
    var only: Set<String> = ["grammar", "model"]
    var model = "qwen3.8:27b"
    var endpoint = ModelEndpoint.defaultURL
    /// Send the editor's warm-up this many seconds before each model instruction.
    var warmLead: Double?

    init(_ arguments: [String]) throws {
        var arguments = arguments[...]
        if let first = arguments.first, !first.hasPrefix("--") { command = first; arguments = arguments.dropFirst() }
        while let argument = arguments.popFirst() {
            switch argument {
            case "--file": file = arguments.popFirst() ?? file
            case "--split": split = arguments.popFirst() ?? split
            case "--only":
                only = Set((arguments.popFirst() ?? "").split(separator: ",").map { $0 == "ollama" ? "model" : String($0) })
            case "--model", "--ollama-model": model = arguments.popFirst() ?? model
            case "--warm": warmLead = try Self.seconds(arguments.popFirst(), for: argument)
            case "--model-endpoint":
                guard let url = arguments.popFirst().flatMap(URL.init(string:)) else {
                    throw EvalError("--model-endpoint needs a URL")
                }
                endpoint = url
            default: throw EvalError("unknown argument \(argument)")
            }
        }
    }

    static func seconds(_ value: String?, for argument: String) throws -> Double {
        guard let seconds = value.flatMap(Double.init), seconds >= 0 else {
            throw EvalError("\(argument) needs a number of seconds")
        }
        return seconds
    }
}

func runInterpreters(_ options: Options) async throws {
    let set = try EvalSet.load(file: options.file)
    let runner = Runner(set: set, split: options.split)
    guard !runner.selected.isEmpty else {
        throw EvalError("no instructions in split \(options.split) of \(options.file)")
    }
    var runs: [(name: String, results: [Scored])] = []
    var notes: [String] = []
    // Alone, the grammar ships reporting names the screen does not show as not found; ahead of a model it
    // declines them so the model can try.
    if options.only.contains("grammar") {
        runs.append(("A grammar", await runner.run(GrammarInterpreter(unknownNames: .reportNotFound))))
    }
    let grammar = await runner.run(GrammarInterpreter(unknownNames: .decline))
    if options.only.contains("apple") {
        if let results = try await runApple(runner) {
            runs.append(("B Apple on-device", results))
            runs.append(("A then B", Runner.chain(grammar: grammar, model: results)))
        } else {
            notes.append("B Apple on-device: not assessed, \(appleModelUnavailableReason() ?? "unknown")")
        }
    }
    if !options.only.isDisjoint(with: ["model", "model-alone"]) {
        let model = ModelInterpreter(endpoint: try ModelEndpoint(url: options.endpoint, model: options.model,
                                                                 timeout: 300))
        // Loads the model, so the first measured instruction does not pay for it.
        _ = try await model.interpret(InterpretRequest(instruction: "circle ok", targets: []))
        if options.only.contains("model") {
            let warm = options.warmLead.map { " warmed \(String(format: "%g", $0)) s ahead" } ?? ""
            let name = "A then model (\(options.model))\(warm)"
            runs.append((name, await runner.runChain(grammar: grammar, model: model, warmLead: options.warmLead)))
        }
        if options.only.contains("model-alone") {
            runs.append(("C model alone (\(options.model))", await runner.run(model)))
        }
    }
    for run in runs {
        let name = run.name.replacingOccurrences(of: " ", with: "_").replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
        try Runner.write(run.results, name: name, split: options.split)
    }
    var summary = ["Run on \(osVersion()), file \(options.file), split \(options.split), "
                   + "\(runner.selected.count) instructions.", ""]
    let splits = options.split == "all" ? Array(Set(runner.selected.map(\.split))).sorted() + ["all"] : [options.split]
    for split in splits {
        summary += ["### \(split)", "", Report.table(runs, split: split), ""] + Report.breakdowns(runs, split: split)
    }
    summary += Report.legend + notes
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
    case "prompts": try await writePrompts(options)
    default: throw EvalError("unknown command \(options.command); use interpret or speech")
    }
} catch {
    log("exhibit-eval: \(error)")
    exit(1)
}

/// The chat the model step would send for each instruction the grammar declines, and its warm-up, one JSON object
/// per line on stdout, for timing direct calls to a model server: `swift run exhibit-eval prompts --split all`.
func writePrompts(_ options: Options) async throws {
    let set = try EvalSet.load(file: options.file)
    let runner = Runner(set: set, split: options.split)
    let grammar = await runner.run(GrammarInterpreter(unknownNames: .decline))
    for (instruction, first) in zip(runner.selected, grammar) where !first.answered {
        let request = set.request(for: instruction)
        let listing = TargetListing(request)
        func chat(_ messages: [ModelMessage]) -> [[String: String]] {
            messages.map { ["role": $0.role.rawValue, "content": $0.content] }
        }
        let object: [String: Any] = [
            "id": instruction.id, "fixture": instruction.fixture,
            "messages": chat(ModelPrompt.messages(for: request, listing: listing)),
            "warmUp": chat(ModelPrompt.warmUpMessages(listing))
        ]
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        print(String(bytes: data, encoding: .utf8) ?? "")
    }
}
