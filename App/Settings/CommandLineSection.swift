import AppKit
import ExhibitShell
import PanelKit
import SwiftUI

extension CommandLineTool {
    /// The command inside this copy of the app, in Contents/MacOS.
    static var app: CommandLineTool {
        CommandLineTool(bundled: Bundle.main.url(forAuxiliaryExecutable: CommandLineTool.name)?.path)
    }
}

/// The `exhibit` command: whether it is linked onto the PATH, a way to link it, and the line that adds the MCP
/// server to Claude Code.
struct CommandLineSection: View {
    let tool: CommandLineTool
    @State private var state: CommandLineTool.State
    @State private var note: String?
    @State private var copied = false

    init(tool: CommandLineTool) {
        self.tool = tool
        _state = State(initialValue: tool.state)
    }

    var body: some View {
        Section {
            LabeledContent {
                switch state {
                case .linked:
                    StatusLight(.go, "Linked")
                case .notLinked:
                    Button("Link…") {
                        note = tool.install().message
                        state = tool.state
                    }
                case .notBundled:
                    Text("Not in this build").foregroundStyle(.secondary)
                }
            } label: {
                Text("Command line tool")
                Text(detail)
            }
            if let line = tool.mcpCommand {
                LabeledContent {
                    Button(copied ? "Copied" : "Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(line, forType: .string)
                        copied = true
                    }
                } label: {
                    Text("MCP server for Claude Code")
                    Text(line).font(.system(size: 11).monospaced()).textSelection(.enabled)
                }
            }
        } header: {
            Text("Command line")
        } footer: {
            Text(note ?? "Lets you, a script or an AI agent capture and mark up from Terminal. Homebrew installs "
                 + "link it for you.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var detail: String {
        switch state {
        case .linked(let path): "exhibit is at \(path)."
        case .notLinked: "Adds a link named exhibit to a folder on your PATH. No password needed."
        case .notBundled: "This copy of Exhibit A has no exhibit command."
        }
    }
}
