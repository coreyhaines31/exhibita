import ExhibitCLI
import ExhibitCore
import ExhibitFixtures
import ExhibitTargets
import Foundation
import Testing

/// `exhibit mcp` as a client runs it: the real binary, JSON-RPC lines on stdin, replies on stdout.
@Suite(.timeLimit(.minutes(2))) struct MCPEndToEndTests {
    @Test func aClientBlursTheEmailsLikeTheCLI() throws {
        let directory = try temporaryDirectory()
        let input = try writePNG(targetsFixture(scale: 2), named: "shot.png", in: directory)
        let viaMCP = directory.appendingPathComponent("mcp.png").path
        let viaCLI = directory.appendingPathComponent("cli.png").path
        let messages: [[String: Any]] = [
            ["jsonrpc": "2.0", "id": 1, "method": "initialize",
             "params": ["protocolVersion": "2025-06-18", "capabilities": [String: Any](),
                        "clientInfo": ["name": "test", "version": "1"]]],
            ["jsonrpc": "2.0", "method": "notifications/initialized"],
            ["jsonrpc": "2.0", "id": 2, "method": "tools/list"],
            ["jsonrpc": "2.0", "id": 3, "method": "tools/call",
             "params": ["name": "mark", "arguments": ["input": input, "kind": "blur", "kinds": ["email"],
                                                      "output": viaMCP]]]
        ]
        let lines = try messages.map { try #require(String(bytes: try JSONSerialization.data(withJSONObject: $0),
                                                           encoding: .utf8)) }
        let result = try runBinary(["mcp"], input: lines.joined(separator: "\n") + "\n")
        #expect(result.status == .success, "\(result.stderr)")

        // Exactly one reply per request, each one JSON-RPC line, in order.
        let replies = try result.stdout.split(separator: "\n").map { try json(String($0)) }
        #expect(replies.map { $0["id"] as? Int } == [1, 2, 3])
        #expect(replies.allSatisfy { $0["jsonrpc"] as? String == "2.0" })
        let tools = try #require((replies[1]["result"] as? [String: Any])?["tools"] as? [[String: Any]])
        #expect(tools.compactMap { $0["name"] as? String } == ["targets", "mark", "apply", "say", "capture", "open"])

        let call = try #require(replies[2]["result"] as? [String: Any])
        #expect(call["isError"] as? Bool == false)
        #expect((call["structuredContent"] as? [String: Any])?["output"] as? String == viaMCP)

        // The emails are gone, and the image is byte for byte what `exhibit blur --kind email` writes.
        let found = try TargetFinder().findTargets(in: try readImage(viaMCP))
        #expect(!found.contains { $0.kind == .email })
        #expect(!found.compactMap(\.text).joined().lowercased().contains("rivera"))
        let cli = try runBinary(["blur", input, "--kind", "email", "-o", viaCLI])
        #expect(cli.status == .success, "\(cli.stderr)")
        #expect(try Data(contentsOf: URL(fileURLWithPath: viaMCP)) == Data(contentsOf: URL(fileURLWithPath: viaCLI)))
    }
}
