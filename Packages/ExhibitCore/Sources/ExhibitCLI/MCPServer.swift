import Foundation

/// `exhibit mcp`: a Model Context Protocol server on stdin and stdout. JSON-RPC 2.0, one message per line. It is a
/// thin wrapper over the file commands (`MCPTools`); stdout carries nothing but JSON-RPC, and logs go to stderr.
/// Requests are handled one at a time, in order.
public final class MCPServer {
    static let latestProtocolVersion = "2025-06-18"
    static let supportedProtocolVersions: Set = ["2025-06-18", "2025-03-26", "2024-11-05"]

    /// The version agreed in `initialize`. `structuredContent` is only sent from 2025-06-18 on.
    private(set) var protocolVersion = MCPServer.latestProtocolVersion

    public init() {}

    /// Serves until `readLine` returns nil (end of input) or `write` fails (the client went away).
    func serve(readLine: () -> String?, write: (String) -> Bool) {
        while let line = readLine() {
            guard let response = handle(line: line) else { continue }
            guard write(response) else { return }
        }
    }

    /// Serves on the process's standard input and output.
    public func serveStandardIO() {
        signal(SIGPIPE, SIG_IGN)
        Self.log("exhibit mcp \(CLI.version): serving on stdin and stdout.")
        serve(readLine: { Swift.readLine(strippingNewline: true) }, write: { line in
            do {
                try FileHandle.standardOutput.write(contentsOf: Data((line + "\n").utf8))
                return true
            } catch {
                return false
            }
        })
    }

    static func log(_ message: String) {
        try? FileHandle.standardError.write(contentsOf: Data((message + "\n").utf8))
    }

    /// Handles one line of input and returns the line to send back, or nil for notifications, responses and
    /// blank lines.
    func handle(line: String) -> String? {
        let text = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        guard let parsed = try? JSONSerialization.jsonObject(with: Data(text.utf8), options: [.fragmentsAllowed]) else {
            Self.log("exhibit mcp: ignored a line that is not JSON.")
            return encode(Self.error(id: NSNull(), code: -32_700, message: "Parse error: the line is not valid JSON."))
        }
        guard let message = parsed as? [String: Any] else {
            return encode(Self.error(id: NSNull(), code: -32_600,
                                     message: "Invalid request: send one JSON-RPC object per line (no batches)."))
        }
        let id = message["id"]
        if message["method"] == nil, id != nil, message["result"] != nil || message["error"] != nil {
            return nil  // A response to a request this server never sends.
        }
        guard message["jsonrpc"] as? String == "2.0", let method = message["method"] as? String,
              id == nil || Self.isValidID(id) else {
            return encode(Self.error(id: Self.isValidID(id) ? id : NSNull(), code: -32_600,
                                     message: "Invalid request: needs \"jsonrpc\": \"2.0\" and a string \"method\"."))
        }
        let params = message["params"] ?? [String: Any]()
        guard let id else { return nil }  // Notifications, notifications/initialized included, need no answer.
        guard let params = params as? [String: Any] else {
            return encode(Self.error(id: id, code: -32_602, message: "Invalid params: \"params\" must be an object."))
        }
        return encode(respond(id: id, method: method, params: params))
    }

    private func respond(id: Any, method: String, params: [String: Any]) -> [String: Any] {
        switch method {
        case "initialize": return Self.result(id: id, initialize(params))
        case "ping": return Self.result(id: id, [String: Any]())
        case "tools/list": return Self.result(id: id, ["tools": MCPTools.definitions()])
        case "tools/call": return callTool(id: id, params: params)
        default: return Self.error(id: id, code: -32_601, message: "Method not found: \(method).")
        }
    }

    private func initialize(_ params: [String: Any]) -> [String: Any] {
        if let requested = params["protocolVersion"] as? String, Self.supportedProtocolVersions.contains(requested) {
            protocolVersion = requested
        } else {
            protocolVersion = Self.latestProtocolVersion
        }
        return [
            "protocolVersion": protocolVersion,
            "capabilities": ["tools": ["listChanged": false]],
            "serverInfo": ["name": "exhibit", "version": CLI.version],
            "instructions": "Exhibit A marks up and redacts screenshot files on this Mac. Call targets to read "
                + "what is on the screen, then mark, apply or say to write a new PNG; results name the file. "
                + MCPTools.untrusted
        ]
    }

    private func callTool(id: Any, params: [String: Any]) -> [String: Any] {
        guard let name = params["name"] as? String else {
            return Self.error(id: id, code: -32_602, message: "Invalid params: tools/call needs a string \"name\".")
        }
        guard MCPTools.names.contains(name) else {
            return Self.error(id: id, code: -32_602, message: "Unknown tool: \(name). Tools: "
                              + MCPTools.names.joined(separator: ", ") + ".")
        }
        let arguments = params["arguments"] ?? [String: Any]()
        guard let arguments = arguments as? [String: Any] else {
            return Self.error(id: id, code: -32_602, message: "Invalid params: \"arguments\" must be an object.")
        }
        let outcome = MCPTools.call(name, arguments: arguments)
        let failed = outcome.status != .success
        let text = (failed ? outcome.stderr : outcome.stdout).trimmingCharacters(in: .whitespacesAndNewlines)
        var result: [String: Any] = ["content": [["type": "text", "text": text]], "isError": failed]
        if protocolVersion >= "2025-06-18",
           let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] {
            result["structuredContent"] = object
        }
        return Self.result(id: id, result)
    }

    /// JSON-RPC ids are strings or numbers. JSON booleans also arrive as NSNumber, so rule them out by type.
    private static func isValidID(_ id: Any?) -> Bool {
        if id is String { return true }
        guard let number = id as? NSNumber else { return false }
        return CFGetTypeID(number) != CFBooleanGetTypeID()
    }

    private static func result(id: Any, _ result: [String: Any]) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "result": result]
    }

    private static func error(id: Any?, code: Int, message: String) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id ?? NSNull(), "error": ["code": code, "message": message]]
    }

    private func encode(_ message: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: message, options: [.sortedKeys,
                                                                                         .withoutEscapingSlashes]),
              let line = String(bytes: data, encoding: .utf8) else {
            return #"{"error":{"code":-32603,"message":"Internal error: could not encode the response."},"id":null,"#
                + #""jsonrpc":"2.0"}"#
        }
        return line
    }
}
