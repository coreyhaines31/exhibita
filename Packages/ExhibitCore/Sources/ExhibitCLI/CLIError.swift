import ExhibitBridge
import ExhibitCore
import ExhibitPlanning
import Foundation

/// Exit codes. Stable: agents branch on them. Documented in `docs/cli.md`.
public enum ExitStatus: Int32, Sendable {
    case success = 0
    /// Files that cannot be read or written, an output that already exists, a render that failed.
    case failure = 1
    /// Bad arguments, a bad `marks.json`, a missing required option.
    case usage = 2
    /// A selector matched nothing, or `--nth` asked for a match that does not exist.
    case noMatch = 3
    /// A selector matched several things and the command draws one mark per selector.
    case ambiguous = 4
    /// `say`: the grammar could not read the instruction and no model is configured.
    case needsModel = 5
    /// `say`: the configured model could not be reached, timed out or gave an answer that could not be read.
    case modelFailed = 6
    /// `capture`, `open`: Exhibit A is not running. The CLI never starts it.
    case appNotRunning = 7
    /// `capture`: Exhibit A does not have Screen Recording. The CLI never asks for it.
    case permissionNotGranted = 8
    /// `capture`: the window is on the never-capture list.
    case neverCapture = 9
    /// `capture`, `open`: Exhibit A did not answer in time.
    case timeout = 10
}

/// One thing a selector matched, as reported in an ambiguous error.
struct CandidateReport: Encodable, Equatable {
    var text: String?
    var kind: String
    var rect: OutputRect
}

/// A failure with a stable `code` string, printed as JSON on stderr.
struct CLIError: Error, Equatable {
    var code: String
    var message: String
    var status: ExitStatus
    /// Selectors that matched nothing.
    var selectors: [String]?
    /// For ambiguous errors: what the selector matched.
    var candidates: [CandidateReport]?
    var hint: String?
    /// For `say`: what the instruction named that is not on the screen.
    var notFound: [String]?
    /// For `capture --window`: the windows an ambiguous name could mean.
    var windows: [WindowSummary]?

    static func usage(_ message: String) -> CLIError {
        CLIError(code: "usage", message: message, status: .usage)
    }

    static func io(_ message: String) -> CLIError {
        CLIError(code: "io", message: message, status: .failure)
    }

    /// Prefixes the message with where in `marks.json` the problem is.
    func inEntry(_ index: Int?) -> CLIError {
        guard let index else { return self }
        var copy = self
        copy.message = "marks[\(index)]: \(message)"
        return copy
    }

    static func from(_ error: Error) -> CLIError {
        if let error = error as? CLIError { return error }
        if let error = error as? PlanError { return CLIError(error) }
        if let error = error as? ExhibitError {
            return CLIError(code: error == .renderFailed ? "render" : "io", message: error.description, status: .failure)
        }
        return CLIError(code: "io", message: error.localizedDescription, status: .failure)
    }

    var json: String {
        struct Envelope: Encodable {
            struct Body: Encodable {
                var code: String
                var message: String
                var exitCode: Int32
                var selectors: [String]?
                var candidates: [CandidateReport]?
                var hint: String?
                var notFound: [String]?
                var windows: [WindowSummary]?
            }
            var error: Body
        }
        let body = Envelope.Body(code: code, message: message, exitCode: status.rawValue, selectors: selectors,
                                 candidates: candidates, hint: hint, notFound: notFound,
                                 windows: windows)
        return OutputJSON.string(Envelope(error: body))
    }
}

extension CLIError {
    /// A planning failure with the CLI's exit code, candidates as reported, and a hint for what matched nothing.
    init(_ error: PlanError) {
        let status: ExitStatus = switch error.code {
        case .usage: .usage
        case .noMatch, .nthOutOfRange: .noMatch
        case .ambiguous: .ambiguous
        }
        self.init(code: error.code.rawValue, message: error.message, status: status, selectors: error.selectors,
                  candidates: error.candidates?.map(\.report))
        if error.code == .noMatch { hint = error.missing.compactMap(SelectorMatcher.hint(for:)).first }
    }
}

/// A rect for output: rounded to a tenth of a pixel so JSON stays readable.
struct OutputRect: Encodable, Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    init(_ rect: PixelRect) {
        let rect = rect.standardized
        x = Self.tenth(rect.x)
        y = Self.tenth(rect.y)
        width = Self.tenth(rect.width)
        height = Self.tenth(rect.height)
    }

    static func tenth(_ value: Double) -> Double { (value * 10).rounded() / 10 }
}

/// A point for output, rounded like `OutputRect`.
struct OutputPoint: Encodable, Equatable {
    var x: Double
    var y: Double

    init(_ point: PixelPoint) {
        x = OutputRect.tenth(point.x)
        y = OutputRect.tenth(point.y)
    }
}

enum OutputJSON {
    static func string(_ value: some Encodable) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value), let text = String(bytes: data, encoding: .utf8) else {
            return #"{"error":{"code":"internal","message":"Could not encode output."}}"#
        }
        return text
    }
}
