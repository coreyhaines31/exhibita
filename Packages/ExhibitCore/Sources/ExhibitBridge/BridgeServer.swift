import Darwin
import Foundation
import os

/// The app's end of the bridge: listens on the socket, and for each connection checks the peer's user id, reads
/// one request line, asks the handler and writes one response line.
///
/// Anything that can reach the socket can read the screen, so: the socket lives in a 0700 directory, is itself
/// 0600, and a peer whose user id is not `allowedUID` (this user) is closed without an answer.
public final class BridgeServer: @unchecked Sendable {
    public typealias Handler = @Sendable (BridgeRequest) async -> BridgeResponse

    private static let logger = Logger(subsystem: "com.exhibitaformac.ExhibitA", category: "Bridge")

    public let socketURL: URL
    private let handler: Handler
    private let allowedUID: uid_t
    private let requestTimeout: TimeInterval
    private let responseTimeout: TimeInterval
    private let queue = DispatchQueue(label: "com.exhibitaformac.ExhibitA.bridge")
    private let lock = NSLock()
    private var source: DispatchSourceRead?

    /// - Parameters:
    ///   - allowedUID: the only user id answered. Tests pass another to check refusals.
    ///   - requestTimeout: how long a client may take to send its request line.
    public init(socketURL: URL, allowedUID: uid_t = getuid(), requestTimeout: TimeInterval = 5,
                responseTimeout: TimeInterval = 10, handler: @escaping Handler) {
        self.socketURL = socketURL
        self.allowedUID = allowedUID
        self.requestTimeout = requestTimeout
        self.responseTimeout = responseTimeout
        self.handler = handler
    }

    deinit {
        stop()
    }

    /// Creates the private directory, replaces a stale socket (never a file that is not a socket, and never one
    /// another process still answers on), binds, sets 0600 and starts accepting.
    public func start() throws {
        let path = socketURL.path
        var address = try BridgeSocket.address(path)
        try BridgeSocket.preparePrivateDirectory(socketURL.deletingLastPathComponent())
        try removeStaleSocket(at: path)

        let descriptor = try BridgeSocket.makeSocket()
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0 else {
            let code = errno
            close(descriptor)
            throw BridgeSocket.Failure.system("bind", code)
        }
        guard chmod(path, 0o600) == 0, listen(descriptor, 16) == 0 else {
            let code = errno
            close(descriptor)
            unlink(path)
            throw BridgeSocket.Failure.system("listen", code)
        }
        BridgeSocket.setNonBlocking(descriptor)
        let source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: queue)
        source.setEventHandler { [weak self] in self?.acceptPending(descriptor) }
        source.setCancelHandler {
            close(descriptor)
            unlink(path)
        }
        lock.withLock { self.source = source }
        source.resume()
    }

    /// Stops accepting and removes the socket. Requests already being answered finish.
    public func stop() {
        let source = lock.withLock { () -> DispatchSourceRead? in
            defer { self.source = nil }
            return self.source
        }
        source?.cancel()
    }

    private func removeStaleSocket(at path: String) throws {
        var info = stat()
        guard lstat(path, &info) == 0 else { return }
        guard info.st_mode & S_IFMT == S_IFSOCK else {
            throw BridgeSocket.Failure.unsafePath("\(path) exists and is not a socket; not replacing it.")
        }
        if let descriptor = try? BridgeSocket.connect(to: path) {
            close(descriptor)
            throw BridgeSocket.Failure.alreadyServing(path)
        }
        unlink(path)
    }

    private func acceptPending(_ listener: Int32) {
        while true {
            let descriptor = accept(listener, nil, nil)
            guard descriptor >= 0 else { return }
            var on: Int32 = 1
            setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
            _ = fcntl(descriptor, F_SETFD, FD_CLOEXEC)
            // Accepted sockets inherit O_NONBLOCK on macOS; reads and writes wait in poll.
            BridgeSocket.setNonBlocking(descriptor)
            guard BridgeSocket.peerUID(descriptor) == allowedUID else {
                Self.logger.error("Refused a bridge connection from another user.")
                close(descriptor)
                continue
            }
            DispatchQueue.global(qos: .userInitiated).async { [self] in serve(descriptor) }
        }
    }

    private func serve(_ descriptor: Int32) {
        let request: BridgeRequest
        do {
            let line = try BridgeSocket.readLine(descriptor, deadline: Date().addingTimeInterval(requestTimeout))
            request = try BridgeJSON.decode(BridgeRequest.self, from: line)
        } catch {
            let unreadable = BridgeError(.badRequest, "The request could not be read.")
            respond(BridgeResponse(id: "", error: unreadable), on: descriptor)
            return
        }
        guard request.v == BridgeProtocol.version else {
            respond(BridgeResponse(id: request.id, error: BridgeError(
                .unsupportedVersion, "This Exhibit A speaks bridge version \(BridgeProtocol.version), the request "
                    + "was version \(request.v). Update Exhibit A and the exhibit command to the same release.")),
                    on: descriptor)
            return
        }
        let handler = handler
        Task.detached { [self] in
            let response = await handler(request)
            respond(response, on: descriptor)
        }
    }

    private func respond(_ response: BridgeResponse, on descriptor: Int32) {
        defer { close(descriptor) }
        guard let data = try? BridgeJSON.encodeLine(response) else { return }
        try? BridgeSocket.writeAll(descriptor, data, deadline: Date().addingTimeInterval(responseTimeout))
    }
}
