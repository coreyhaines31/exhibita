import ExhibitCore
import Foundation

/// The capture policy on disk: `~/Library/Application Support/Exhibit A/policy.json` (`docs/format.md`). One file,
/// so a team or a managed profile can supply it later. A missing file means the defaults; so does a file that
/// cannot be read, so a damaged file never turns protection off.
public struct CapturePolicyFile: Sendable {
    public static let fileName = "policy.json"
    public static let currentFormatVersion = 1

    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// `policy.json` in the given Application Support directory (`ExhibitPaths.supportDirectory()`).
    public init(supportDirectory: URL) {
        url = supportDirectory.appendingPathComponent(Self.fileName)
    }

    public struct Loaded: Equatable, Sendable {
        public var policy: CapturePolicy
        /// Why the file was not used, when it exists but could not be read. The defaults apply.
        public var problem: String?

        public init(policy: CapturePolicy, problem: String? = nil) {
            self.policy = policy
            self.problem = problem
        }
    }

    public func load() -> Loaded {
        guard FileManager.default.fileExists(atPath: url.path) else { return Loaded(policy: CapturePolicy()) }
        do {
            return Loaded(policy: try Self.decode(try Data(contentsOf: url)))
        } catch {
            return Loaded(policy: CapturePolicy(), problem: "\(url.path) could not be read, so the default policy "
                          + "applies: \(error)")
        }
    }

    public func save(_ policy: CapturePolicy) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.encode(policy).write(to: url, options: .atomic)
    }

    // MARK: Coding

    private struct Stored: Codable {
        struct AutoBlur: Codable {
            var enabled: Bool?
            var kinds: [String]?
        }
        var formatVersion: Int
        var neverCapture: [NeverCaptureApp]?
        var agentAutoBlur: AutoBlur?
    }

    public enum Problem: Error, CustomStringConvertible, Equatable {
        case newerVersion(Int)

        public var description: String {
            switch self {
            case .newerVersion(let version):
                "formatVersion \(version) is newer than this version of Exhibit A reads (\(currentFormatVersion))"
            }
        }
    }

    /// Missing fields take their defaults; an explicit empty list stays empty.
    public static func decode(_ data: Data) throws -> CapturePolicy {
        let stored = try JSONDecoder().decode(Stored.self, from: data)
        guard stored.formatVersion <= currentFormatVersion else { throw Problem.newerVersion(stored.formatVersion) }
        let defaults = CapturePolicy()
        return CapturePolicy(
            neverCapture: stored.neverCapture ?? defaults.neverCapture,
            agentAutoBlur: stored.agentAutoBlur?.enabled ?? defaults.agentAutoBlur,
            autoBlurKinds: stored.agentAutoBlur?.kinds?.map(TargetKind.init(rawValue:)) ?? defaults.autoBlurKinds
        )
    }

    public static func encode(_ policy: CapturePolicy) throws -> Data {
        let stored = Stored(formatVersion: currentFormatVersion, neverCapture: policy.neverCapture,
                            agentAutoBlur: .init(enabled: policy.agentAutoBlur,
                                                 kinds: policy.autoBlurKinds.map(\.rawValue)))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(stored)
    }
}

/// Where Exhibit A keeps things: one Application Support directory holding history, the policy file and the
/// bridge socket. `EXHIBIT_SUPPORT_DIR` moves all of it, for tests; nothing else should set it.
public enum ExhibitPaths {
    public static let supportOverrideVariable = "EXHIBIT_SUPPORT_DIR"

    /// `~/Library/Application Support/Exhibit A`, or `$EXHIBIT_SUPPORT_DIR` when set.
    public static func supportDirectory(environment: [String: String] = ProcessInfo.processInfo.environment)
        -> URL {
        if let override = environment[supportOverrideVariable], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true).standardizedFileURL
        }
        let library = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return library.appendingPathComponent("Exhibit A", isDirectory: true)
    }

    public static func capturesDirectory(in support: URL) -> URL {
        support.appendingPathComponent("Captures", isDirectory: true)
    }
}
