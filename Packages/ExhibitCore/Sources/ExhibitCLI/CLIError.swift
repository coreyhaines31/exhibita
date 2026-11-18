import ExhibitCore
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
            }
            var error: Body
        }
        let body = Envelope.Body(code: code, message: message, exitCode: status.rawValue, selectors: selectors,
                                 candidates: candidates, hint: hint)
        return OutputJSON.string(Envelope(error: body))
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
