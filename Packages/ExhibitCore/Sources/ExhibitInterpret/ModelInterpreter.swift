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

    public init(endpoint: ModelEndpoint, transport: any ModelTransport = URLSessionModelTransport()) {
        self.endpoint = endpoint
        self.transport = transport
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
