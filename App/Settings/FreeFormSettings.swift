import ExhibitInterpret
import Foundation
import Observation

/// The free-form instructions setting, kept in `Preferences.defaults`, and the Test button's last result. One
/// shared instance: Settings edits it and every editor reads it when the grammar declines.
@MainActor
@Observable
final class FreeFormSettings {
    static let shared = FreeFormSettings()
    static let key = "freeFormModel"

    var settings: ModelSettings {
        didSet {
            guard settings != oldValue else { return }
            save()
            probe = nil
        }
    }

    /// What the Test button found, or nil before it is pressed and after a change.
    var probe: ModelProbeResult?
    var isTesting = false

    init(settings: ModelSettings? = nil) {
        self.settings = settings ?? Self.load()
    }

    /// The interpreter for what the grammar declines, or nil when free-form instructions are off or no model is
    /// named. A setting that can't be used (a host other than this Mac) becomes an interpreter that fails with
    /// the reason, so the editor says why and nothing is sent.
    func interpreter() -> (any Interpreter)? {
        do {
            return try settings.modelEndpoint().map { ModelInterpreter(endpoint: $0) }
        } catch let error as ModelError {
            return FailingInterpreter(error: error)
        } catch {
            return FailingInterpreter(error: .invalidEndpoint(error.localizedDescription))
        }
    }

    /// Sends one tiny request off the main thread and records what came back.
    func test() {
        guard !isTesting else { return }
        isTesting = true
        probe = nil
        let settings = settings
        Task {
            let result = await Task.detached { ModelProbe.run(settings) }.value
            if settings == self.settings { probe = result }
            isTesting = false
        }
    }

    private func save() {
        Preferences.defaults.set(try? JSONEncoder().encode(settings), forKey: Self.key)
    }

    private static func load() -> ModelSettings {
        guard let data = Preferences.defaults.data(forKey: key),
              let settings = try? JSONDecoder().decode(ModelSettings.self, from: data) else { return ModelSettings() }
        return settings
    }
}

/// Stands in for a model whose setting can't be used, so the reason reaches the person.
private struct FailingInterpreter: Interpreter {
    let error: ModelError
    var name: String { "model" }

    func interpret(_ request: InterpretRequest) async throws -> InterpretOutcome {
        throw error
    }
}
