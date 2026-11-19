import ExhibitCore
import ExhibitInterpret
import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Why Apple's on-device model cannot be used here, or nil when it can.
func appleModelUnavailableReason() -> String? {
    #if canImport(FoundationModels)
    guard #available(macOS 26.0, *) else { return "needs macOS 26 (this is \(osVersion()))" }
    switch SystemLanguageModel.default.availability {
    case .available: return nil
    case .unavailable(let reason): return "unavailable: \(reason)"
    }
    #else
    return "the FoundationModels framework is not in this SDK"
    #endif
}

func osVersion() -> String {
    let version = ProcessInfo.processInfo.operatingSystemVersion
    return "macOS \(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
}

#if canImport(FoundationModels)
/// Apple's on-device model through FoundationModels, with guided generation: the answer is decoded against a
/// schema whose refs are the listed targets, so it can only name targets that exist.
@available(macOS 26.0, *)
struct AppleModelInterpreter: Interpreter {
    var name: String { "apple-on-device" }

    func interpret(_ request: InterpretRequest) async throws -> InterpretOutcome {
        let listing = TargetListing(request)
        let session = LanguageModelSession(instructions: ModelPrompt.instructions)
        let options = GenerationOptions(samplingMode: .greedy, maximumResponseTokens: ModelPrompt.maxResponseTokens)
        let response = try await session.respond(to: ModelPrompt.prompt(for: request, listing: listing),
                                                 schema: try Self.schema(refs: listing.refs), options: options)
        return .understood(try ModelPrompt.interpretation(fromJSON: response.rawContent.jsonString, listing: listing))
    }

    func warmUp() async throws {
        let session = LanguageModelSession(instructions: ModelPrompt.instructions)
        _ = try await session.respond(to: "Say ok.")
    }

    static func schema(refs: [String]) throws -> GenerationSchema {
        let ref = DynamicGenerationSchema(name: "Ref", description: "A ref from the screen list",
                                          anyOf: refs.isEmpty ? ["none"] : refs)
        let mark = DynamicGenerationSchema(name: "Mark", anyOf: MarkKind.allCases.map(\.rawValue))
        let targets = DynamicGenerationSchema(arrayOf: ref, maximumElements: ModelPrompt.maxTargets)
        let part = DynamicGenerationSchema(name: "Part", properties: [
            .init(name: "words", description: "The person's words for the thing, copied from the instruction",
                  schema: DynamicGenerationSchema(type: String.self)),
            .init(name: "mark", schema: mark),
            .init(name: "targets", schema: targets),
            .init(name: "label", description: "Words for a text mark or an arrow caption",
                  schema: DynamicGenerationSchema(type: String.self), isOptional: true)
        ])
        let root = DynamicGenerationSchema(name: "Answer", properties: [
            .init(name: "parts", schema: DynamicGenerationSchema(arrayOf: part, maximumElements: ModelPrompt.maxParts))
        ])
        return try GenerationSchema(root: root, dependencies: [])
    }
}
#endif
