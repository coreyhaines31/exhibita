import ExhibitInterpret
import Foundation
import Observation

/// The setting for instructions in the person's own words, kept in `Preferences.defaults`; what discovery last
/// found on this Mac; and the Test button's last result. One shared instance: Settings edits it and every editor
/// reads it when the built-in commands decline.
@MainActor
@Observable
final class FreeFormSettings {
    typealias Discoverer = @Sendable () async -> Discovery

    /// Looks for nothing until launch sets its `discoverer` (`AppDelegate.lookForModelServers`), so renders and
    /// view tests never touch the network.
    static let shared = FreeFormSettings()
    static let key = "freeFormModel"

    /// Asks Ollama and an OpenAI-compatible server on this Mac for their models (`ModelDiscovery`).
    static let live: Discoverer = {
        await ModelDiscovery.discover { url, timeout in try URLSessionModelTransport().get(url, timeout: timeout) }
    }

    /// Finds nothing and sends nothing, for the end-to-end tests.
    static let offline: Discoverer = {
        Discovery(probes: ModelDiscovery.candidates.map { .notRunning($0.kind, $0.url) })
    }

    /// A never-chosen setting that found nothing looks again for an instruction that needs a model only after
    /// this long; until then such an instruction says at once that it needs one.
    static let retryAfter: Duration = .seconds(30)

    var settings: ModelSettings {
        didSet {
            guard settings != oldValue else { return }
            save()
            probe = nil
        }
    }

    /// What the last discovery found; nil before the first one answers.
    private(set) var discovery: Discovery?
    private(set) var isDiscovering = false
    /// How discovery is done; nil never looks (renders with a fixed `discovery`).
    var discoverer: Discoverer?
    private var discovering: Task<Discovery, Never>?
    private var discoveredAt: ContinuousClock.Instant?

    /// What the Test button found, or nil before it is pressed and after a change.
    var probe: ModelProbeResult?
    var isTesting = false

    init(settings: ModelSettings? = nil, discovery: Discovery? = nil, discoverer: Discoverer? = nil) {
        self.settings = settings ?? Self.load()
        self.discovery = discovery
        self.discoverer = discoverer
    }

    /// The line under the picker.
    var status: ModelStatus { settings.status(discovery: discovery) }

    /// Looks for model servers on this Mac, off the main thread, and keeps what it finds. A look already under
    /// way is joined, not repeated. Runs when Settings opens, on Check Again, once at launch, and when an
    /// instruction needs a model and none was found.
    @discardableResult
    func refresh() -> Task<Discovery, Never>? {
        if let discovering { return discovering }
        guard let discoverer else { return nil }
        isDiscovering = true
        let task = Task.detached(priority: .userInitiated) { await discoverer() }
        discovering = task
        Task {
            let found = await task.value
            discovery = found
            discoveredAt = .now
            isDiscovering = false
            discovering = nil
        }
        return task
    }

    /// The model step for what the built-in commands decline, at once and without looking: the model in effect,
    /// nil when None is chosen or nothing was found in the last `retryAfter`, or, when never chosen and nothing is
    /// known yet, a `LazyModelInterpreter` that looks for a server on this Mac only if the grammar declines.
    func interpreter() -> (any Interpreter)? {
        guard settings.effectiveChoice == nil, discovery?.defaultChoice == nil else { return currentInterpreter() }
        if let discoveredAt, ContinuousClock.now - discoveredAt <= Self.retryAfter { return nil }
        return LazyModelInterpreter { [weak self] in await self?.lookThenInterpreter() }
    }

    /// Looks for a server (joining a look under way), then the model in effect.
    private func lookThenInterpreter() async -> (any Interpreter)? {
        if let task = refresh() {
            discovery = await task.value
            discoveredAt = .now
        }
        return currentInterpreter()
    }

    /// The interpreter from what is known now, without looking. A setting that can't be used (a host other than
    /// this Mac) becomes an interpreter that fails with the reason, so the editor says why and nothing is sent.
    func currentInterpreter() -> (any Interpreter)? {
        do {
            return try settings.endpoint(discovery: discovery).map { ModelInterpreter(endpoint: $0) }
        } catch let error as ModelError {
            return FailingInterpreter(error: error)
        } catch {
            return FailingInterpreter(error: .invalidEndpoint(error.localizedDescription))
        }
    }

    /// Sends one tiny request to the model in effect off the main thread and records what came back.
    func test() {
        guard !isTesting, let endpoint = try? settings.endpoint(discovery: discovery) else { return }
        isTesting = true
        probe = nil
        let settings = settings
        let probed = ModelSettings(enabled: true, endpoint: endpoint.url.absoluteString, model: endpoint.model,
                                   api: endpoint.api == .openai ? .openai : .ollama, choice: .other)
        Task {
            let result = await Task.detached { ModelProbe.run(probed) }.value
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
