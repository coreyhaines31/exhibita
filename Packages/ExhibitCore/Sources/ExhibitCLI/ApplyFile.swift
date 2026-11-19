import ExhibitCore
import ExhibitPlanning
import Foundation

/// `marks.json` for `exhibit apply`: an array of entries, or `{"marks": [...]}`. Each entry is one mark command,
/// using the same selectors as the flags or explicit geometry. Unknown fields are an error, so a typo never
/// silently drops a selector. The format is documented in `docs/cli.md`.
enum ApplyFile {
    static func specs(from data: Data) throws -> [MarkSpec] {
        let entries: [Entry]
        do {
            let decoder = JSONDecoder()
            guard let top = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
                throw invalid("marks.json is not valid JSON.")
            }
            if top is [String: Any] {
                entries = try decoder.decode(Wrapper.self, from: data).marks
            } else {
                entries = try decoder.decode([Entry].self, from: data)
            }
        } catch let error as CLIError {
            throw error
        } catch let error as DecodingError {
            throw invalid(describe(error))
        }
        guard !entries.isEmpty else { throw invalid("marks.json has no marks.") }
        return entries.map(\.spec)
    }

    static func invalid(_ message: String) -> CLIError {
        CLIError(code: "invalid_marks", message: message, status: .usage)
    }

    private static func describe(_ error: DecodingError) -> String {
        let (context, what): (DecodingError.Context, String) = switch error {
        case let .typeMismatch(_, context): (context, "has the wrong type")
        case let .valueNotFound(_, context): (context, "is missing a value")
        case let .keyNotFound(key, context): (context, "needs \"\(key.stringValue)\"")
        case let .dataCorrupted(context): (context, "is invalid")
        @unknown default: (DecodingError.Context(codingPath: [], debugDescription: ""), "is invalid")
        }
        var path = context.codingPath.map { $0.intValue.map { "[\($0)]" } ?? ".\($0.stringValue)" }.joined()
        if path.hasPrefix(".marks") { path.removeFirst(6) }
        let location = path.isEmpty ? "marks.json" : "marks" + path
        let detail = context.debugDescription.isEmpty ? "" : " (\(context.debugDescription))"
        return "\(location) \(what)\(detail)."
    }

    private struct Wrapper: Decodable {
        var marks: [Entry]
    }

    private struct AnyKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    /// A string or an array of strings, a rect or an array of rects.
    private struct OneOrMany<Value: Decodable>: Decodable {
        var values: [Value]

        init(from decoder: Decoder) throws {
            if let many = try? [Value](from: decoder) {
                values = many
            } else {
                values = [try Value(from: decoder)]
            }
        }
    }

    /// `to` is a selector string, or a point for an arrow drawn by coordinates.
    private enum Destination: Decodable {
        case text(String)
        case point(PixelPoint)

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let text = try? container.decode(String.self) {
                self = .text(text)
            } else {
                self = .point(try container.decode(PixelPoint.self))
            }
        }
    }

    static let fields: Set<String> = ["kind", "text", "regex", "to", "kinds", "rect", "from", "label", "color",
                                      "number", "all", "nth", "allowMissing"]

    private struct Entry: Decodable {
        var spec: MarkSpec

        private enum Keys: String, CodingKey {
            case kind, text, regex, to, kinds, rect, from, label, color, number, all, nth, allowMissing
        }

        init(from decoder: Decoder) throws {
            let raw = try decoder.container(keyedBy: AnyKey.self)
            if let unknown = raw.allKeys.map(\.stringValue).sorted().first(where: { !ApplyFile.fields.contains($0) }) {
                throw ApplyFile.invalid("\(Self.location(decoder)) has an unknown field \"\(unknown)\". Fields: "
                                        + ApplyFile.fields.sorted().joined(separator: ", ") + ".")
            }
            let container = try decoder.container(keyedBy: Keys.self)
            let kindName = try container.decode(String.self, forKey: .kind)
            guard let kind = MarkKind(rawValue: kindName) else {
                throw ApplyFile.invalid("\(Self.location(decoder)) has an unknown kind \"\(kindName)\". Kinds: "
                                        + MarkKind.allCases.map(\.rawValue).joined(separator: ", ") + ".")
            }
            var spec = MarkSpec(kind: kind)
            spec.selectors += try container.decodeIfPresent(OneOrMany<PixelRect>.self, forKey: .rect)?.values
                .map(Selector.rect) ?? []
            spec.selectors += try container.decodeIfPresent(OneOrMany<String>.self, forKey: .text)?.values
                .map(Selector.text) ?? []
            switch try container.decodeIfPresent(Destination.self, forKey: .to) {
            case .text(let text): spec.selectors.append(.text(text))
            case .point(let point): spec.toPoint = point
            case nil: break
            }
            spec.selectors += try container.decodeIfPresent(OneOrMany<String>.self, forKey: .regex)?.values
                .map(Selector.regex) ?? []
            do {
                spec.selectors += try (container.decodeIfPresent(OneOrMany<String>.self, forKey: .kinds)?.values ?? [])
                    .map { .kind(try Selector.parseKind($0)) }
            } catch let error as CLIError {
                throw ApplyFile.invalid("\(Self.location(decoder)): \(error.message)")
            }
            spec.from = try container.decodeIfPresent(PixelPoint.self, forKey: .from)
            spec.label = try container.decodeIfPresent(String.self, forKey: .label)
            if let colorName = try container.decodeIfPresent(String.self, forKey: .color) {
                guard let color = MarkColor(rawValue: colorName) else {
                    throw ApplyFile.invalid("\(Self.location(decoder)) has an unknown color \"\(colorName)\".")
                }
                spec.color = color
            }
            spec.number = try container.decodeIfPresent(Int.self, forKey: .number)
            spec.all = try container.decodeIfPresent(Bool.self, forKey: .all) ?? false
            spec.nth = try container.decodeIfPresent(Int.self, forKey: .nth)
            spec.allowMissing = try container.decodeIfPresent(Bool.self, forKey: .allowMissing) ?? false
            self.spec = spec
        }

        static func location(_ decoder: Decoder) -> String {
            let index = decoder.codingPath.last?.intValue
            return index.map { "marks[\($0)]" } ?? "A mark"
        }
    }
}
