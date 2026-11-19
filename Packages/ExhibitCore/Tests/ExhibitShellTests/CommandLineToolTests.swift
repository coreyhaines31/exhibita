import ExhibitShell
import Foundation
import Testing

/// Real files in a temporary folder: a fake `Exhibit A.app/Contents/MacOS/exhibit` and fake PATH folders.
@Suite struct CommandLineToolTests {
    let root: URL
    let bundled: String
    let homebrew: String
    let system: String
    let user: String

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("exhibit-cli-\(UUID().uuidString)")
        let macOS = root.appendingPathComponent("Applications/Exhibit A.app/Contents/MacOS")
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        bundled = macOS.appendingPathComponent("exhibit").path
        FileManager.default.createFile(atPath: bundled, contents: Data("#!/bin/sh\n".utf8))
        homebrew = root.appendingPathComponent("opt/homebrew/bin").path
        system = root.appendingPathComponent("usr/local/bin").path
        user = root.appendingPathComponent("home/.local/bin").path
    }

    private func tool(bundled: String? = nil) -> CommandLineTool {
        CommandLineTool(bundled: bundled ?? self.bundled, directories: [homebrew, system, user], userDirectory: user)
    }

    private func makeFolder(_ path: String) throws {
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    }

    @Test func aBuildWithoutTheCommandSaysSo() {
        let missing = CommandLineTool(bundled: nil, directories: [homebrew], userDirectory: user)
        #expect(missing.state == .notBundled)
        #expect(missing.install() == .notBundled)
        #expect(missing.mcpCommand == nil)
        #expect(tool(bundled: root.appendingPathComponent("nothing").path).state == .notBundled)
    }

    @Test func linksIntoHomebrewsFolderWhenItIsWritable() throws {
        try makeFolder(homebrew)
        let tool = tool()
        #expect(tool.state == .notLinked)
        #expect(tool.install() == .linked("\(homebrew)/exhibit"))
        #expect(tool.state == .linked("\(homebrew)/exhibit"))
        #expect(tool.install() == .alreadyLinked("\(homebrew)/exhibit"))
        #expect(!FileManager.default.fileExists(atPath: user), "no fallback folder made")
    }

    @Test func fallsBackToLocalBinAndSaysToAddItToThePath() throws {
        let tool = tool()
        let result = tool.install()
        #expect(result == .linked("\(user)/exhibit"))
        #expect(result.message.contains("add ~/.local/bin to your PATH"))
        #expect(tool.state == .linked("\(user)/exhibit"))
    }

    @Test func seesTheCasksLinkAsInstalled() throws {
        try makeFolder(system)
        try FileManager.default.createSymbolicLink(atPath: "\(system)/exhibit", withDestinationPath: bundled)
        #expect(tool().state == .linked("\(system)/exhibit"))
    }

    @Test func neverReplacesSomethingElse() throws {
        try makeFolder(homebrew)
        FileManager.default.createFile(atPath: "\(homebrew)/exhibit", contents: Data("other".utf8))
        let result = tool().install()
        #expect(result == .linked("\(user)/exhibit"), "skips to the next folder")
        #expect(try String(contentsOfFile: "\(homebrew)/exhibit", encoding: .utf8) == "other")

        let onlyHomebrew = CommandLineTool(bundled: bundled, directories: [homebrew], userDirectory: user)
        let occupied = onlyHomebrew.install()
        #expect(occupied == .occupied(["\(homebrew)/exhibit"]))
        #expect(occupied.message.contains("left it alone"))
    }

    @Test func replacesALinkToAnOlderCopy() throws {
        try makeFolder(homebrew)
        let old = root.appendingPathComponent("Downloads/Exhibit A.app/Contents/MacOS/exhibit").path
        try FileManager.default.createSymbolicLink(atPath: "\(homebrew)/exhibit", withDestinationPath: old)
        #expect(tool().state == .notLinked, "a dangling link is not installed")
        #expect(tool().install() == .linked("\(homebrew)/exhibit"))
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: "\(homebrew)/exhibit") == bundled)
    }

    @Test func mcpLineQuotesPathsWithSpaces() throws {
        let tool = tool()
        #expect(tool.mcpCommand == "claude mcp add exhibit -- '\(bundled)' mcp")
        try makeFolder(homebrew)
        _ = tool.install()
        #expect(tool.mcpCommand == "claude mcp add exhibit -- \(homebrew)/exhibit mcp")
        #expect(CommandLineTool.shellQuoted("/a/it's") == "'/a/it'\\''s'")
    }

    @Test func defaultFoldersArePreferredInOrder() {
        let tool = CommandLineTool(bundled: nil, home: "/Users/example")
        #expect(tool.directories == ["/opt/homebrew/bin", "/usr/local/bin", "/Users/example/.local/bin"])
        #expect(tool.userDirectory == "/Users/example/.local/bin")
    }
}
