import ExhibitCore
import Foundation

/// The HTTP reply of a model endpoint.
public struct ModelHTTPResponse: Sendable, Equatable {
    public var status: Int
    public var body: Data

    public init(status: Int, body: Data) {
        self.status = status
        self.body = body
    }
}

/// Sends one request to a model endpoint and waits for the reply. Blocking, so the CLI can call it from plain
/// synchronous code; tests inject a fake one so no real model runs in unit tests.
public protocol ModelTransport: Sendable {
    func post(_ url: URL, body: Data, timeout: TimeInterval) throws -> ModelHTTPResponse
    /// A `GET`, for asking a server what it has loaded. A transport that cannot throws `ModelError.unreachable`.
    func get(_ url: URL, timeout: TimeInterval) throws -> ModelHTTPResponse
}

extension ModelTransport {
    public func get(_ url: URL, timeout: TimeInterval) throws -> ModelHTTPResponse {
        throw ModelError.unreachable("\(url.absoluteString) (GET is not supported)")
    }
}

/// Loopback HTTP with URLSession: no proxy, no cache, no cookies, and no redirects, so a reply can never send the
/// request on to another host.
public struct URLSessionModelTransport: ModelTransport {
    public init() {}

    public func post(_ url: URL, body: Data, timeout: TimeInterval) throws -> ModelHTTPResponse {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        return try send(request, timeout: timeout)
    }

    /// A `GET` on this Mac, for `ModelDiscovery`'s model lists; the same rules as `post`.
    public func get(_ url: URL, timeout: TimeInterval) throws -> ModelHTTPResponse {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.httpMethod = "GET"
        return try send(request, timeout: timeout)
    }

    private func send(_ request: URLRequest, timeout: TimeInterval) throws -> ModelHTTPResponse {
        guard let url = request.url, let host = url.host, ModelEndpoint.isLoopback(host) else {
            throw ModelError.notLoopback(request.url?.host ?? request.url?.absoluteString ?? "no URL")
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = [:]
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        let session = URLSession(configuration: configuration, delegate: RefuseRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        let reply = ReplyBox()
        let done = DispatchSemaphore(value: 0)
        let task = session.dataTask(with: request) { data, response, error in
            reply.set(data: data, response: response, error: error)
            done.signal()
        }
        task.resume()
        if done.wait(timeout: .now() + timeout + 1) == .timedOut {
            task.cancel()
            throw ModelError.timedOut(timeout)
        }
        let (data, response, error) = (reply.data, reply.response, reply.error)
        if let error = error as? URLError {
            if error.code == .timedOut { throw ModelError.timedOut(timeout) }
            throw ModelError.unreachable("\(url.absoluteString) (\(error.localizedDescription))")
        }
        if let error { throw ModelError.unreachable(error.localizedDescription) }
        guard let http = response as? HTTPURLResponse else { throw ModelError.unreachable("no HTTP reply") }
        return ModelHTTPResponse(status: http.statusCode, body: data ?? Data())
    }

    private final class RefuseRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }

    /// Written once by the completion handler, read after the semaphore.
    private final class ReplyBox: @unchecked Sendable {
        private let lock = NSLock()
        private var storedData: Data?
        private var storedResponse: URLResponse?
        private var storedError: Error?

        func set(data: Data?, response: URLResponse?, error: Error?) {
            lock.withLock {
                storedData = data
                storedResponse = response
                storedError = error
            }
        }

        var data: Data? { lock.withLock { storedData } }
        var response: URLResponse? { lock.withLock { storedResponse } }
        var error: Error? { lock.withLock { storedError } }
    }
}

/// The free-form tier: a local model, for what the grammar declines.
///
/// It sends the instruction and the target listing (refs, kinds, text with secrets masked, boxes), never the image
/// and never a secret. It does not rely on structured output: the format is in the prompt, the JSON is read
/// leniently, and every ref is checked against the listing, so a model can only ever mark targets that were found.
/// It always answers (understood, possibly with every part not found) or throws a `ModelError`; it never declines.
public struct ModelInterpreter: Interpreter {
    public let endpoint: ModelEndpoint
    public let transport: any ModelTransport
    /// Which screen was last warmed up; shared by every interpreter of the app unless a test passes its own.
    public let warmUps: ModelWarmUps
    /// When this app last asked a model an instruction; shared likewise.
    public let use: ModelUse

    public init(endpoint: ModelEndpoint, transport: any ModelTransport = URLSessionModelTransport(),
                warmUps: ModelWarmUps = .shared, use: ModelUse = .shared) {
        self.endpoint = endpoint
        self.transport = transport
        self.warmUps = warmUps
        self.use = use
    }

    public var name: String { "model" }

    public func interpret(_ request: InterpretRequest) async throws -> InterpretOutcome {
        try await interpretWithTimings(request).outcome
    }

    /// Interprets on the calling thread, blocking until the model answers or the timeout passes.
    public func interpretNow(_ request: InterpretRequest) throws -> InterpretOutcome {
        try interpretTimed(request).outcome
    }

    /// `interpret`, plus what the server reported about the call, for the eval.
    public func interpretWithTimings(_ request: InterpretRequest) async throws
        -> (outcome: InterpretOutcome, timings: ModelTimings?) {
        // The transport blocks, so it runs off Swift concurrency's cooperative pool.
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(with: Result { try interpretTimed(request) })
            }
        }
    }

    /// `interpretNow`, plus what the server reported about the call.
    public func interpretTimed(_ request: InterpretRequest) throws
        -> (outcome: InterpretOutcome, timings: ModelTimings?) {
        use.record()
        let listing = TargetListing(request)
        let reply = try send(ModelPrompt.messages(for: request, listing: listing),
                             maxTokens: ModelPrompt.maxResponseTokens)
        let content = try endpoint.content(of: reply.body)
        let interpretation = try ModelPrompt.interpretation(fromJSON: ModelPrompt.jsonObject(in: content),
                                                            listing: listing)
        return (.understood(interpretation), endpoint.timings(of: reply.body))
    }

    /// Sends a chat and returns the reply, or throws for anything but HTTP 200.
    private func send(_ messages: [ModelMessage], maxTokens: Int) throws -> ModelHTTPResponse {
        let body = try endpoint.body(messages: messages, maxTokens: maxTokens)
        var reply = try transport.post(endpoint.chatURL, body: body, timeout: endpoint.timeout)
        if reply.status == 400, endpoint.api == .openai {
            // A server that refuses the switches that turn reasoning off: ask again without them.
            let plain = try endpoint.body(messages: messages, maxTokens: maxTokens, noReasoning: false)
            reply = try transport.post(endpoint.chatURL, body: plain, timeout: endpoint.timeout)
        }
        guard reply.status == 200 else {
            throw ModelError.httpStatus(reply.status, ModelEndpoint.preview(reply.body))
        }
        return reply
    }
}

// MARK: - Warming up

/// An interpreter that can read a screen before the instruction for it arrives.
public protocol ScreenWarming: Sendable {
    /// Starts reading the screen in the background and returns at once. Never throws and never waits.
    func warmUp(_ targets: [Target])
    /// The same, but only if this app used the model recently and it is still loaded in its server, so nothing new
    /// is loaded into memory and a model loaded for other work is left alone. Returns at once.
    func warmUpIfLoaded(_ targets: [Target])
}

extension ModelInterpreter: ScreenWarming {
    /// Has the model read the system prompt and the screen while the person is still speaking or typing, so the
    /// instruction's request only reads the instruction (`docs/product/model-latency.md`). It sends exactly the
    /// start of the request `interpret` will send, with a one-token answer, and loads the model if it was unloaded.
    ///
    /// At most once per screen and model (`ModelWarmUps`). Its answer is dropped, and a failure is ignored: the
    /// instruction's own request reports any problem. An instruction the built-in commands answer simply leaves
    /// the warm-up unused.
    public func warmUp(_ targets: [Target]) {
        DispatchQueue.global(qos: .utility).async {
            _ = try? warmUpNow(targets)
        }
    }

    /// `warmUp` for when an editor opens, only when this app asked the model an instruction in the last
    /// `ModelUse.recentWindow` and the server still has it in memory (`isLoaded`). So the screen is read before the
    /// person starts an instruction without loading a model, and someone who loaded the model for other work and
    /// does not use it here gets no GPU work from Exhibit A and no keep-alive reset. Without recent use the server
    /// is not even asked.
    public func warmUpIfLoaded(_ targets: [Target]) {
        guard use.isRecent() else { return }
        DispatchQueue.global(qos: .utility).async {
            guard isLoaded() else { return }
            _ = try? warmUpNow(targets)
        }
    }

    /// Whether the server has this model loaded now: Ollama's `GET /api/ps`, on this Mac only, with a one-second
    /// timeout. False for an OpenAI-compatible server, which has no such list, and when anything fails.
    public func isLoaded() -> Bool {
        guard endpoint.api == .ollama else { return false }
        let base = endpoint.chatURL.deletingLastPathComponent().deletingLastPathComponent()
        guard let reply = try? transport.get(base.appendingPathComponent("api/ps"), timeout: 1), reply.status == 200,
              let object = try? JSONSerialization.jsonObject(with: reply.body) as? [String: Any],
              let models = object["models"] as? [[String: Any]] else { return false }
        let wanted = endpoint.model.contains(":") ? [endpoint.model] : [endpoint.model, endpoint.model + ":latest"]
        return models.contains { entry in
            [entry["name"], entry["model"]].contains { ($0 as? String).map(wanted.contains) == true }
        }
    }

    /// Sends the warm-up on the calling thread. Returns the server's timings, or nil when nothing was sent because
    /// there is nothing to read or this screen was the last one read recently.
    @discardableResult
    public func warmUpNow(_ targets: [Target]) throws -> ModelTimings? {
        let listing = TargetListing(InterpretRequest(instruction: "", targets: targets))
        guard !listing.entries.isEmpty else { return nil }
        let messages = ModelPrompt.warmUpMessages(listing)
        let key = ModelWarmUps.Key(url: endpoint.chatURL, model: endpoint.model, screen: messages.last?.content ?? "")
        guard warmUps.claim(key) else { return nil }
        do {
            let reply = try send(messages, maxTokens: ModelPrompt.warmUpResponseTokens)
            return endpoint.timings(of: reply.body) ?? ModelTimings()
        } catch {
            warmUps.release(key)
            throw error
        }
    }
}

/// When this app run last asked a model an instruction (one the built-in commands declined; answered or not), so
/// an editor opening warms the screen only for someone using the model here now.
public final class ModelUse: @unchecked Sendable {
    /// The one the app's interpreters share.
    public static let shared = ModelUse()
    public static let recentWindow: Duration = .seconds(600)

    private let lock = NSLock()
    private let now: @Sendable () -> ContinuousClock.Instant
    private var last: ContinuousClock.Instant?

    public init(now: @escaping @Sendable () -> ContinuousClock.Instant = { ContinuousClock.now }) {
        self.now = now
    }

    /// The model step is running now.
    public func record() {
        lock.withLock { last = now() }
    }

    /// Whether the model was asked within `window`.
    public func isRecent(within window: Duration = recentWindow) -> Bool {
        lock.withLock {
            guard let last else { return false }
            return now() - last <= window
        }
    }
}

/// Which screen a model server last read ahead of an instruction. Runners keep the cache of about one screen,
/// so a screen is warmed again once another was warmed after it, or once the server has likely unloaded the model
/// (Ollama's `keep_alive` is five minutes by default); otherwise not.
public final class ModelWarmUps: @unchecked Sendable {
    public struct Key: Hashable, Sendable {
        var url: URL
        var model: String
        var screen: String
    }

    /// The one the app's editors share.
    public static let shared = ModelWarmUps()

    private let lock = NSLock()
    private let staleAfter: Duration
    private let now: @Sendable () -> ContinuousClock.Instant
    private var last: (key: Key, at: ContinuousClock.Instant)?

    public init(staleAfter: Duration = .seconds(240),
                now: @escaping @Sendable () -> ContinuousClock.Instant = { ContinuousClock.now }) {
        self.staleAfter = staleAfter
        self.now = now
    }

    /// Whether to warm this screen now; if so, it counts as the last one warmed.
    func claim(_ key: Key) -> Bool {
        lock.withLock {
            let time = now()
            if let last, last.key == key, time - last.at < staleAfter { return false }
            last = (key, time)
            return true
        }
    }

    /// A warm-up that failed, so the next one is tried.
    func release(_ key: Key) {
        lock.withLock {
            if last?.key == key { last = nil }
        }
    }
}
