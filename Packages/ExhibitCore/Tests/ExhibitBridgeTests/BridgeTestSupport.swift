@testable import ExhibitBridge
import Foundation

/// A short private directory for one test's socket. Unix socket paths are limited to 103 bytes, and the system
/// temporary directory is long, so this lives under /tmp. It never touches the real Application Support.
func shortTemporaryDirectory() throws -> URL {
    let url = URL(fileURLWithPath: "/tmp", isDirectory: true)
        .appendingPathComponent("exb-\(UUID().uuidString.prefix(8))", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func socketURL() throws -> URL {
    BridgeSocket.url(inSupportDirectory: try shortTemporaryDirectory())
}
