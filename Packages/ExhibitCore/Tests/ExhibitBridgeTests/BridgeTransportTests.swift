import Darwin
@testable import ExhibitBridge
import Foundation
import Testing

/// The socket server and client against each other in process. Every socket lives in its own /tmp directory;
/// nothing here touches the real app's socket.
@Suite(.serialized, .timeLimit(.minutes(1))) struct BridgeTransportTests {
    static let echo: BridgeServer.Handler = { request in
        BridgeResponse(id: request.id, pong: request.method == "ping")
    }

    @Test func pingRoundTrip() throws {
        let url = try socketURL()
        let server = BridgeServer(socketURL: url, handler: Self.echo)
        try server.start()
        defer { server.stop() }
        let response = try BridgeClient(socketURL: url, timeout: 5).send(BridgeRequest(id: "p", method: .ping))
        #expect(response == BridgeResponse(id: "p", pong: true))
    }

    @Test func socketIsPrivate() throws {
        let url = try socketURL()
        let server = BridgeServer(socketURL: url, handler: Self.echo)
        try server.start()
        defer { server.stop() }
        #expect(BridgeSocket.mode(of: url.path) == 0o600)
        #expect(BridgeSocket.mode(of: url.deletingLastPathComponent().path) == 0o700)
        var info = stat()
        #expect(lstat(url.path, &info) == 0)
        #expect(info.st_mode & S_IFMT == S_IFSOCK)
        #expect(info.st_uid == getuid())
    }

    @Test func tightensAnExistingDirectory() throws {
        let url = try socketURL()
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        chmod(directory.path, 0o755)
        let server = BridgeServer(socketURL: url, handler: Self.echo)
        try server.start()
        defer { server.stop() }
        #expect(BridgeSocket.mode(of: directory.path) == 0o700)
    }

    @Test func refusesPeersOfAnotherUser() throws {
        let url = try socketURL()
        // Pretend this user is someone else: the server must close without answering.
        let server = BridgeServer(socketURL: url, allowedUID: getuid() &+ 1, handler: Self.echo)
        try server.start()
        defer { server.stop() }
        #expect(throws: BridgeClient.Failure.self) {
            try BridgeClient(socketURL: url, timeout: 5).send(BridgeRequest(method: .ping))
        }
        do {
            _ = try BridgeClient(socketURL: url, timeout: 5).send(BridgeRequest(method: .ping))
        } catch let failure as BridgeClient.Failure {
            guard case .protocolError = failure else {
                Issue.record("Expected a protocol error, got \(failure)")
                return
            }
        }
    }

    @Test func clientRefusesAServerOfAnotherUser() throws {
        let url = try socketURL()
        let server = BridgeServer(socketURL: url, handler: Self.echo)
        try server.start()
        defer { server.stop() }
        #expect(throws: BridgeClient.Failure.self) {
            try BridgeClient(socketURL: url, timeout: 5, expectedUID: getuid() &+ 1).send(BridgeRequest(method: .ping))
        }
    }

    @Test func noSocketMeansAppNotRunning() throws {
        let url = try socketURL()
        #expect(throws: BridgeClient.Failure.appNotRunning) {
            try BridgeClient(socketURL: url, timeout: 1).send(BridgeRequest(method: .ping))
        }
    }

    @Test func staleSocketMeansAppNotRunningAndIsReplaced() throws {
        let url = try socketURL()
        let first = BridgeServer(socketURL: url, handler: Self.echo)
        try first.start()
        // Leave a socket file nobody listens on, as a crash would.
        let stale = try BridgeSocket.makeSocket()
        first.stop()
        var address = try BridgeSocket.address(url.path)
        Thread.sleep(forTimeInterval: 0.1)
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(stale, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        #expect(bound == 0)
        close(stale)
        #expect(throws: BridgeClient.Failure.appNotRunning) {
            try BridgeClient(socketURL: url, timeout: 1).send(BridgeRequest(method: .ping))
        }
        let second = BridgeServer(socketURL: url, handler: Self.echo)
        try second.start()
        defer { second.stop() }
        #expect(try BridgeClient(socketURL: url, timeout: 5).send(BridgeRequest(method: .ping)).pong == true)
    }

    @Test func refusesToStartTwiceOrOverAFile() throws {
        let url = try socketURL()
        let server = BridgeServer(socketURL: url, handler: Self.echo)
        try server.start()
        defer { server.stop() }
        #expect(throws: BridgeSocket.Failure.alreadyServing(url.path)) {
            try BridgeServer(socketURL: url, handler: Self.echo).start()
        }

        let other = try socketURL()
        try FileManager.default.createDirectory(at: other.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not a socket".utf8).write(to: other)
        #expect(throws: BridgeSocket.Failure.self) { try BridgeServer(socketURL: other, handler: Self.echo).start() }
        #expect(FileManager.default.fileExists(atPath: other.path))
    }

    @Test func clientTimesOut() throws {
        let url = try socketURL()
        let server = BridgeServer(socketURL: url) { request in
            try? await Task.sleep(for: .seconds(3))
            return BridgeResponse(id: request.id, pong: true)
        }
        try server.start()
        defer { server.stop() }
        let started = Date()
        #expect(throws: BridgeClient.Failure.timedOut(0.3)) {
            try BridgeClient(socketURL: url, timeout: 0.3).send(BridgeRequest(method: .ping))
        }
        #expect(Date().timeIntervalSince(started) < 2)
    }

    @Test func serverDropsASilentClient() throws {
        let url = try socketURL()
        let server = BridgeServer(socketURL: url, requestTimeout: 0.2, handler: Self.echo)
        try server.start()
        defer { server.stop() }
        let descriptor = try BridgeSocket.connect(to: url.path)
        defer { close(descriptor) }
        let line = try BridgeSocket.readLine(descriptor, deadline: Date().addingTimeInterval(3))
        let response = try BridgeJSON.decode(BridgeResponse.self, from: line)
        #expect(response.error?.code == "bad_request")
    }

    @Test func refusesOtherVersionsAndGarbage() throws {
        let url = try socketURL()
        let server = BridgeServer(socketURL: url, handler: Self.echo)
        try server.start()
        defer { server.stop() }
        let newer = try BridgeClient(socketURL: url, timeout: 5).send(BridgeRequest(id: "n", method: .ping, version: 2))
        #expect(newer.error?.code == "unsupported_version")
        #expect(newer.id == "n")

        let descriptor = try BridgeSocket.connect(to: url.path)
        defer { close(descriptor) }
        try BridgeSocket.writeAll(descriptor, Data("{nope\n".utf8), deadline: Date().addingTimeInterval(2))
        let line = try BridgeSocket.readLine(descriptor, deadline: Date().addingTimeInterval(3))
        #expect(try BridgeJSON.decode(BridgeResponse.self, from: line).error?.code == "bad_request")
    }

    @Test func pathsThatAreTooLongAreRefused() {
        let long = "/tmp/" + String(repeating: "a", count: 120) + "/bridge.sock"
        #expect(throws: BridgeSocket.Failure.pathTooLong(long)) { try BridgeSocket.address(long) }
    }

    @Test func manyClientsAtOnce() async throws {
        let url = try socketURL()
        let server = BridgeServer(socketURL: url, handler: Self.echo)
        try server.start()
        defer { server.stop() }
        let ids = try await withThrowingTaskGroup(of: String.self) { group in
            for index in 0..<8 {
                group.addTask {
                    try BridgeClient(socketURL: url, timeout: 5).send(BridgeRequest(id: "c\(index)", method: .ping)).id
                }
            }
            return try await group.reduce(into: Set<String>()) { $0.insert($1) }
        }
        #expect(ids.count == 8)
    }
}
