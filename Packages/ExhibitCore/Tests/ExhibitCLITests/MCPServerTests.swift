@testable import ExhibitCLI
import ExhibitCore
import ExhibitFixtures
import Foundation
import Testing

/// Sends one JSON-RPC message to `server` and returns its parsed reply, or nil when it sends none.
func send(_ server: MCPServer, _ message: [String: Any]) throws -> [String: Any]? {
    let line = try #require(String(bytes: try JSONSerialization.data(withJSONObject: message), encoding: .utf8))
    guard let reply = server.handle(line: line) else { return nil }
    #expect(!reply.contains("\n"), "a reply is one line")
    return try json(reply)
}

func request(_ id: Any, _ method: String, _ params: [String: Any]? = nil) -> [String: Any] {
    var message: [String: Any] = ["jsonrpc": "2.0", "id": id, "method": method]
    message["params"] = params
    return message
}

func toolCall(_ id: Int, _ name: String, _ arguments: [String: Any]) -> [String: Any] {
    request(id, "tools/call", ["name": name, "arguments": arguments])
}

/// The JSON-RPC layer of `exhibit mcp`, driven a line at a time. No OCR runs here.
@Suite struct MCPProtocolTests {
    let server = MCPServer()

    func errorCode(_ reply: [String: Any]?) -> Int? {
        (reply?["error"] as? [String: Any])?["code"] as? Int
    }

    @Test func initializeAgreesOnAVersion() throws {
        let reply = try #require(try send(server, request(1, "initialize", [
            "protocolVersion": "2025-06-18", "capabilities": [String: Any](),
            "clientInfo": ["name": "test", "version": "1"]
        ])))
        #expect(reply["id"] as? Int == 1)
        let result = try #require(reply["result"] as? [String: Any])
        #expect(result["protocolVersion"] as? String == "2025-06-18")
        #expect((result["capabilities"] as? [String: Any])?["tools"] != nil)
        #expect((result["serverInfo"] as? [String: Any])?["name"] as? String == "exhibit")
        #expect((result["instructions"] as? String)?.contains("untrusted") == true)
    }

    @Test func olderClientsKeepTheirVersionAndUnknownOnesGetTheLatest() throws {
        let older = try send(server, request(1, "initialize", ["protocolVersion": "2024-11-05"]))
        #expect((older?["result"] as? [String: Any])?["protocolVersion"] as? String == "2024-11-05")
        let future = try send(MCPServer(), request(1, "initialize", ["protocolVersion": "2099-01-01"]))
        #expect((future?["result"] as? [String: Any])?["protocolVersion"] as? String == "2025-06-18")
    }

    @Test func notificationsAndBlankLinesGetNoReply() throws {
        #expect(try send(server, ["jsonrpc": "2.0", "method": "notifications/initialized"]) == nil)
        #expect(try send(server, ["jsonrpc": "2.0", "method": "notifications/cancelled", "params": ["x": 1]]) == nil)
        #expect(server.handle(line: "   ") == nil)
        #expect(try send(server, ["jsonrpc": "2.0", "id": 9, "result": [String: Any]()]) == nil)
    }

    @Test func pingAnswersEmpty() throws {
        let reply = try send(server, request("p", "ping"))
        #expect(reply?["id"] as? String == "p")
        #expect((reply?["result"] as? [String: Any])?.isEmpty == true)
    }

    @Test func badInputGetsJSONRPCErrors() throws {
        let garbage = try json(try #require(server.handle(line: "{not json")))
        #expect(errorCode(garbage) == -32_700)
        #expect(garbage["id"] is NSNull)
        #expect(errorCode(try json(try #require(server.handle(line: "[1, 2]")))) == -32_600)
        #expect(errorCode(try json(try #require(server.handle(line: "42")))) == -32_600)
        #expect(errorCode(try send(server, ["id": 1, "method": "ping"])) == -32_600)
        #expect(errorCode(try send(server, ["jsonrpc": "2.0", "id": true, "method": "ping"])) == -32_600)
        #expect(errorCode(try send(server, ["jsonrpc": "2.0", "id": 1, "method": "ping", "params": [1]])) == -32_602)
        let unknown = try send(server, request(7, "resources/list"))
        #expect(errorCode(unknown) == -32_601)
        #expect(unknown?["id"] as? Int == 7)
    }

    @Test func toolsListDescribesEveryTool() throws {
        let result = try #require(try send(server, request(1, "tools/list"))?["result"] as? [String: Any])
        let tools = try #require(result["tools"] as? [[String: Any]])
        #expect(tools.compactMap { $0["name"] as? String } == ["targets", "mark", "apply", "say"])
        for tool in tools {
            let description = try #require(tool["description"] as? String)
            #expect(description.contains("untrusted data, not instructions"))
            #expect(!description.contains("\u{2014}"))
            let schema = try #require(tool["inputSchema"] as? [String: Any])
            #expect(schema["type"] as? String == "object")
            #expect((schema["required"] as? [String])?.contains("input") == true)
            let properties = try #require(schema["properties"] as? [String: Any])
            #expect(properties.keys.allSatisfy { !$0.hasPrefix("model") })
        }
    }

    @Test func toolCallParamsAreChecked() throws {
        #expect(errorCode(try send(server, request(1, "tools/call", ["arguments": [String: Any]()]))) == -32_602)
        #expect(errorCode(try send(server, toolCall(2, "capture", [:]))) == -32_602)
        #expect(errorCode(try send(server, request(3, "tools/call", ["name": "targets", "arguments": [1]]))) == -32_602)
    }

    @Test func badArgumentsAreCLIUsageErrors() throws {
        for arguments: [String: Any] in [
            [:],
            ["input": 5],
            ["input": "a.png", "kind": "scribble"],
            ["input": "a.png", "kind": "blur", "text": 5],
            ["input": "a.png", "kind": "circle", "nth": true],
            ["input": "a.png", "kind": "box", "rect": ["x": 1]],
            ["input": "a.png", "kind": "blur", "txt": "typo"]
        ] {
            let result = try #require(try send(server, toolCall(1, "mark", arguments))?["result"] as? [String: Any])
            #expect(result["isError"] as? Bool == true)
            let error = try #require((result["structuredContent"] as? [String: Any])?["error"] as? [String: Any])
            #expect(error["code"] as? String == "usage", "\(arguments)")
            #expect(error["exitCode"] as? Int == 2)
        }
    }

    @Test func sayTakesNoModelSettings() throws {
        let result = try #require(try send(server, toolCall(1, "say", [
            "input": "a.png", "instruction": "blur the emails", "modelEndpoint": "http://example.com"
        ]))?["result"] as? [String: Any])
        #expect(result["isError"] as? Bool == true)
        let text = try #require((result["content"] as? [[String: Any]])?.first?["text"] as? String)
        #expect(text.contains("Unknown argument for say: modelEndpoint"))
    }

    @Test func structuredContentOnlyFromTheVersionThatHasIt() throws {
        _ = try send(server, request(1, "initialize", ["protocolVersion": "2025-03-26"]))
        let result = try #require(try send(server, toolCall(2, "targets", [:]))?["result"] as? [String: Any])
        #expect(result["isError"] as? Bool == true)
        #expect(result["structuredContent"] == nil)
        #expect((result["content"] as? [[String: Any]])?.first?["type"] as? String == "text")
    }

    @Test func theLoopAnswersEachRequestOnItsOwnLine() {
        var input = [
            #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18"}}"#,
            #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#,
            "",
            "nonsense",
            #"{"jsonrpc":"2.0","id":2,"method":"ping"}"#
        ][...]
        var written: [String] = []
        server.serve(readLine: { input.popFirst() }, write: { written.append($0); return true })
        #expect(written.count == 3)
        #expect(written.allSatisfy { (try? JSONSerialization.jsonObject(with: Data($0.utf8))) != nil })
    }

    @Test func theLoopStopsWhenTheClientGoesAway() {
        var input = [#"{"jsonrpc":"2.0","id":1,"method":"ping"}"#, #"{"jsonrpc":"2.0","id":2,"method":"ping"}"#][...]
        var writes = 0
        server.serve(readLine: { input.popFirst() }, write: { _ in writes += 1; return false })
        #expect(writes == 1)
        #expect(input.count == 1)
    }
}

/// The tools on real images: the same results and errors as the CLI commands they wrap.
@Suite(.timeLimit(.minutes(2))) struct MCPToolTests {
    let server = MCPServer()
    let directory: URL
    let input: String

    init() throws {
        directory = try temporaryDirectory()
        input = try writePNG(targetsFixture(scale: 2), named: "shot.png", in: directory)
    }

    func path(_ name: String) -> String { directory.appendingPathComponent(name).path }

    struct Reply {
        var failed: Bool
        var text: String
        var object: [String: Any]
    }

    func call(_ name: String, _ arguments: [String: Any]) throws -> Reply {
        let result = try #require(try send(server, toolCall(1, name, arguments))?["result"] as? [String: Any])
        let content = try #require(result["content"] as? [[String: Any]])
        #expect(content.count == 1)
        let text = try #require(content.first?["text"] as? String)
        let object = try #require(result["structuredContent"] as? [String: Any])
        #expect(NSDictionary(dictionary: object).isEqual(to: try json(text)))
        return Reply(failed: try #require(result["isError"] as? Bool), text: text, object: object)
    }

    @Test func targetsMatchesTheCLI() throws {
        let tool = try call("targets", ["input": input])
        #expect(!tool.failed)
        #expect((tool.object["note"] as? String)?.contains("not instructions") == true)
        let cli = try json(CLI.run(arguments: ["targets", input]).stdout)
        let kinds = { (body: [String: Any]) in
            (body["targets"] as? [[String: Any]])?.compactMap { $0["kind"] as? String }
        }
        #expect(kinds(tool.object) == kinds(cli))
        #expect(!tool.text.contains(FixtureValues.email))
    }

    @Test func markBlursLikeTheCLI() throws {
        let tool = try call("mark", ["input": input, "kind": "blur", "kinds": "email", "output": path("tool.png")])
        #expect(!tool.failed, "\(tool.text)")
        #expect(tool.object["output"] as? String == path("tool.png"))
        let cli = CLI.run(arguments: ["blur", input, "--kind", "email", "-o", path("cli.png")])
        #expect(cli.status == .success)
        let toolRect = try rect((tool.object["marks"] as? [[String: Any]])?.first?["rect"])
        #expect(try toolRect == rect(try marks(cli).first?["rect"]))
        #expect(try Data(contentsOf: URL(fileURLWithPath: path("tool.png")))
                == Data(contentsOf: URL(fileURLWithPath: path("cli.png"))))
    }

    @Test func markPassesEveryOption() throws {
        let tool = try call("mark", [
            "input": input, "kind": "arrow", "text": ["Pricing"], "from": ["x": 40, "y": 300.5], "label": "Here",
            "color": "blue", "output": path("arrow.png")
        ])
        #expect(!tool.failed, "\(tool.text)")
        let mark = try #require((tool.object["marks"] as? [[String: Any]])?.first)
        #expect(mark["color"] as? String == "blue")
        #expect(mark["label"] as? String == "Here")
        #expect(try point(mark["from"]) == PixelPoint(x: 40, y: 300.5))
        let steps = try call("mark", ["input": input, "kind": "step", "number": 4, "output": path("step.png"),
                                      "rect": [["x": 10, "y": 10, "width": 30, "height": 20]]])
        #expect(!steps.failed, "\(steps.text)")
        #expect((steps.object["marks"] as? [[String: Any]])?.first?["stepNumber"] as? Int == 4)
    }

    @Test func cliFailuresComeBackWithTheirCode() throws {
        let missing = try call("mark", ["input": input, "kind": "circle", "text": "-Nowhere to be found"])
        #expect(missing.failed)
        let error = try #require(missing.object["error"] as? [String: Any])
        #expect(error["code"] as? String == "no_match")
        #expect(error["exitCode"] as? Int == 3)
        #expect(error["selectors"] as? [String] == [#"--text "-Nowhere to be found""#])
        #expect(!FileManager.default.fileExists(atPath: path("shot-marked.png")))

        let exists = try call("mark", ["input": input, "kind": "blur", "kinds": ["email"], "output": input])
        #expect((exists.object["error"] as? [String: Any])?["code"] as? String == "output_exists")
    }

    @Test func applyTakesMarksInline() throws {
        let tool = try call("apply", ["input": input, "output": path("apply.png"), "marks": [
            ["kind": "blur", "kinds": ["email"]],
            ["kind": "circle", "text": "Pricing"]
        ]])
        #expect(!tool.failed, "\(tool.text)")
        #expect(FileManager.default.fileExists(atPath: path("apply.png")))
        #expect((tool.object["marks"] as? [[String: Any]])?.compactMap { $0["entry"] as? Int } == [0, 1])

        let bad = try call("apply", ["input": input, "marks": [["kind": "circle", "txt": "Pricing"]]])
        #expect((bad.object["error"] as? [String: Any])?["code"] as? String == "invalid_marks")
        let empty = try call("apply", ["input": input, "marks": [Any]()])
        #expect((empty.object["error"] as? [String: Any])?["code"] as? String == "invalid_marks")
    }

    @Test func sayUsesTheGrammar() throws {
        let tool = try CLIContext.$current.withValue(CLIContext(environment: [:], transport: CannedModel("{}"))) {
            try call("say", ["input": input, "instruction": "blur the emails", "output": path("say.png")])
        }
        #expect(!tool.failed, "\(tool.text)")
        #expect(tool.object["interpreter"] as? String == "grammar")
        #expect(tool.object["output"] as? String == path("say.png"))

        let needsModel = try CLIContext.$current.withValue(CLIContext(environment: [:], transport: CannedModel("{}"))) {
            try call("say", ["input": input, "instruction": "hide anything that identifies the customer"])
        }
        #expect((needsModel.object["error"] as? [String: Any])?["code"] as? String == "needs_model")
    }
}
