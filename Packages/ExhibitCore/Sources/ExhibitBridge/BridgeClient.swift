import Darwin
import Foundation

/// The CLI's end of the bridge. Blocking, so the CLI stays synchronous. It never starts the app: when nothing is
/// serving the socket it says so, and the person opens Exhibit A.
public struct BridgeClient: Sendable {
    public enum Failure: Error, Equatable, CustomStringConvertible {
        /// No socket, or nobody listening on it.
        case appNotRunning
        /// No answer within the timeout.
        case timedOut(TimeInterval)
        /// The socket is served by another user, or the answer was not a bridge response.
        case protocolError(String)

        public var description: String {
            switch self {
            case .appNotRunning: "Exhibit A is not running."
            case .timedOut(let seconds): "Exhibit A did not answer within \(Int(seconds.rounded())) seconds."
            case .protocolError(let reason): reason
            }
        }
    }

    public let socketURL: URL
    public let timeout: TimeInterval
    private let expectedUID: uid_t

    public init(socketURL: URL, timeout: TimeInterval = 30, expectedUID: uid_t = getuid()) {
        self.socketURL = socketURL
        self.timeout = timeout
        self.expectedUID = expectedUID
    }

    /// Sends one request and waits for its response.
    public func send(_ request: BridgeRequest) throws -> BridgeResponse {
        let deadline = Date().addingTimeInterval(timeout)
        let descriptor: Int32
        do {
            descriptor = try BridgeSocket.connect(to: socketURL.path)
        } catch BridgeSocket.Failure.system(_, let code) where [ENOENT, ECONNREFUSED, ENOTDIR].contains(code) {
            throw Failure.appNotRunning
        } catch {
            throw Failure.protocolError("Could not connect to Exhibit A at \(socketURL.path): \(error)")
        }
        defer { close(descriptor) }
        // The server must be this user too, so another account cannot stand in for the app.
        guard BridgeSocket.peerUID(descriptor) == expectedUID else {
            throw Failure.protocolError("\(socketURL.path) is served by another user; refusing to use it.")
        }
        BridgeSocket.setNonBlocking(descriptor)
        do {
            try BridgeSocket.writeAll(descriptor, try BridgeJSON.encodeLine(request), deadline: deadline)
            let line = try BridgeSocket.readLine(descriptor, deadline: deadline)
            let response = try BridgeJSON.decode(BridgeResponse.self, from: line)
            guard response.id == request.id || response.id.isEmpty else {
                throw Failure.protocolError("Exhibit A answered a different request.")
            }
            return response
        } catch BridgeSocket.IOFailure.timedOut {
            throw Failure.timedOut(timeout)
        } catch let failure as Failure {
            throw failure
        } catch BridgeSocket.IOFailure.closed {
            throw Failure.protocolError("Exhibit A closed the connection without answering.")
        } catch {
            throw Failure.protocolError("Exhibit A's answer could not be read: \(error)")
        }
    }
}
