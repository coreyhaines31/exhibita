import Foundation

/// The `exhibit` command bundled in the app (`Contents/MacOS/exhibit`) and its link onto the PATH, for people who
/// didn't install with Homebrew (the cask links it already). Linking never asks for an administrator: it uses the
/// first folder the person can write to, falling back to `~/.local/bin`, and never replaces a file that isn't a
/// link to some copy of Exhibit A's command.
public struct CommandLineTool: Sendable {
    public static let name = "exhibit"

    /// The command inside the running app, or nil when this copy doesn't carry one (a Debug build).
    public var bundled: String?
    /// Where a link may go, in order of preference.
    public var directories: [String]
    /// The person's own folder, created when nothing earlier in `directories` is writable.
    public var userDirectory: String

    public init(bundled: String?, directories: [String], userDirectory: String) {
        self.bundled = bundled
        self.directories = directories
        self.userDirectory = userDirectory
    }

    /// Homebrew's folders first (Apple silicon, then Intel), then `~/.local/bin`.
    public init(bundled: String?, home: String = NSHomeDirectory()) {
        let user = (home as NSString).appendingPathComponent(".local/bin")
        self.init(bundled: bundled, directories: ["/opt/homebrew/bin", "/usr/local/bin", user], userDirectory: user)
    }

    public enum State: Equatable, Sendable {
        case notBundled
        case notLinked
        /// A link at this path resolves to the bundled command.
        case linked(String)
    }

    public var state: State {
        guard let bundled, let real = Self.realPath(bundled) else { return .notBundled }
        for directory in directories {
            let link = Self.path(in: directory)
            if Self.realPath(link) == real { return .linked(link) }
        }
        return .notLinked
    }

    public enum InstallResult: Equatable, Sendable {
        case notBundled
        case alreadyLinked(String)
        case linked(String)
        /// Every writable folder already holds an `exhibit` that isn't ours.
        case occupied([String])
        case failed(String)

        public var message: String {
            switch self {
            case .notBundled:
                "This copy of Exhibit A doesn't include the exhibit command. Download the latest version from "
                    + "exhibitaformac.com."
            case .alreadyLinked(let path):
                "The exhibit command is already linked at \(path)."
            case .linked(let path):
                CommandLineTool.isUserFolder(path)
                    ? "Linked the exhibit command at \(path). If a new Terminal window can't find it, add "
                        + "~/.local/bin to your PATH."
                    : "Linked the exhibit command at \(path). Open a new Terminal window to use it."
            case .occupied(let paths):
                "Something else is already at \(paths.joined(separator: " and ")), so Exhibit A left it alone."
            case .failed(let reason):
                "Couldn't link the exhibit command: \(reason)"
            }
        }
    }

    /// Links the command into the first writable folder, replacing only an older link to Exhibit A's command.
    public func install() -> InstallResult {
        guard let bundled, Self.realPath(bundled) != nil else { return .notBundled }
        if case .linked(let path) = state { return .alreadyLinked(path) }
        let manager = FileManager.default
        var occupied: [String] = []
        for directory in directories {
            if directory == userDirectory, !manager.fileExists(atPath: directory) {
                do {
                    try manager.createDirectory(atPath: directory, withIntermediateDirectories: true)
                } catch {
                    return .failed(error.localizedDescription)
                }
            }
            guard manager.isWritableFile(atPath: directory) else { continue }
            let link = Self.path(in: directory)
            if Self.exists(link) {
                guard Self.isOurs(link) else {
                    occupied.append(link)
                    continue
                }
                do { try manager.removeItem(atPath: link) } catch { return .failed(error.localizedDescription) }
            }
            do {
                try manager.createSymbolicLink(atPath: link, withDestinationPath: bundled)
                return .linked(link)
            } catch {
                return .failed(error.localizedDescription)
            }
        }
        return occupied.isEmpty ? .failed("no folder on the PATH can be written to.") : .occupied(occupied)
    }

    /// The line that adds Exhibit A's MCP server to Claude Code: the link when there is one, else the command in
    /// the app.
    public var mcpCommand: String? {
        let path: String
        switch state {
        case .linked(let link): path = link
        case .notLinked: path = bundled ?? Self.name
        case .notBundled: return nil
        }
        return "claude mcp add exhibit -- \(Self.shellQuoted(path)) mcp"
    }

    // MARK: - Helpers

    static func path(in directory: String) -> String {
        (directory as NSString).appendingPathComponent(name)
    }

    static func isUserFolder(_ path: String) -> Bool {
        path.hasSuffix("/.local/bin/\(name)")
    }

    /// Whether the path is a link to some copy of Exhibit A's command, like one from an earlier install.
    static func isOurs(_ path: String) -> Bool {
        let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: path)
        return destination?.hasSuffix(".app/Contents/MacOS/\(name)") == true
    }

    /// True for a file, a folder or a link, even one whose target is gone.
    static func exists(_ path: String) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: path)) != nil
    }

    /// The path with every link resolved, or nil when nothing is there.
    static func realPath(_ path: String) -> String? {
        guard let real = realpath(path, nil) else { return nil }
        defer { free(real) }
        return String(cString: real)
    }

    /// Single quotes, so a path with spaces ("Exhibit A.app") pastes as one argument.
    public static func shellQuoted(_ text: String) -> String {
        guard text.contains(where: { !($0.isLetter || $0.isNumber || "/._-".contains($0)) }) else { return text }
        return "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
