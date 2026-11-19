import ExhibitCore
import Foundation

/// The app or window a capture would include.
public struct CaptureSubject: Equatable, Sendable {
    public var bundleIdentifier: String?
    public var appName: String?

    public init(bundleIdentifier: String? = nil, appName: String? = nil) {
        self.bundleIdentifier = bundleIdentifier
        self.appName = appName
    }
}

/// One app that is never captured. Matched by bundle identifier, and by name as a fallback, so an entry still
/// holds when an app's bundle identifier changes between versions or is not known.
public struct NeverCaptureApp: Codable, Equatable, Hashable, Sendable {
    public var name: String
    public var bundleIdentifier: String?

    public init(name: String, bundleIdentifier: String? = nil) {
        self.name = name
        self.bundleIdentifier = bundleIdentifier
    }

    public func matches(_ subject: CaptureSubject) -> Bool {
        if let mine = bundleIdentifier.map(Self.fold), !mine.isEmpty,
           let theirs = subject.bundleIdentifier.map(Self.fold), mine == theirs {
            return true
        }
        let name = Self.fold(name)
        guard !name.isEmpty, let theirs = subject.appName.map(Self.fold) else { return false }
        return name == theirs
    }

    private static func fold(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

/// What may be captured, and what an agent's copy hides. Every capture, by a person or an agent, asks this one
/// place. It is stored as one file (`CapturePolicyFile`) so a team or a managed profile can supply it later.
public struct CapturePolicy: Equatable, Sendable {
    public enum Decision: Equatable, Sendable {
        case allow
        /// Never capture the subject: a window capture is refused, and in a region or screen capture its windows
        /// are left out and drawn black with this reason on the label.
        case blackOut(reason: String)
    }

    public var neverCapture: [NeverCaptureApp]
    /// Blur detected sensitive targets in the image an agent receives. The original in history is untouched.
    public var agentAutoBlur: Bool
    /// The target kinds auto-blur covers.
    public var autoBlurKinds: [TargetKind]

    /// Password managers and Keychain Access. An entry matches by bundle identifier or by name, so a wrong
    /// identifier never loses a match. Dashlane's and LastPass's identifiers come from third-party app catalogs,
    /// not from an install we checked (`docs/product/capture-bridge.md`).
    public static let defaultNeverCapture: [NeverCaptureApp] = [
        NeverCaptureApp(name: "1Password", bundleIdentifier: "com.1password.1password"),
        NeverCaptureApp(name: "1Password 7", bundleIdentifier: "com.agilebits.onepassword7"),
        NeverCaptureApp(name: "Bitwarden", bundleIdentifier: "com.bitwarden.desktop"),
        NeverCaptureApp(name: "Dashlane", bundleIdentifier: "com.dashlane.Dashlane"),
        NeverCaptureApp(name: "LastPass", bundleIdentifier: "com.lastpass.lastpassmacdesktop"),
        NeverCaptureApp(name: "KeePassXC", bundleIdentifier: "org.keepassxc.keepassxc"),
        NeverCaptureApp(name: "Passwords", bundleIdentifier: "com.apple.Passwords"),
        NeverCaptureApp(name: "Passwords", bundleIdentifier: "com.apple.Passwords.MenuBarExtra"),
        NeverCaptureApp(name: "Keychain Access", bundleIdentifier: "com.apple.keychainaccess")
    ]

    public static let defaultAutoBlurKinds: [TargetKind] = [.email, .key, .card, .phone]

    /// The defaults: password managers and Keychain Access never captured, auto-blur on.
    public init(neverCapture: [NeverCaptureApp] = Self.defaultNeverCapture, agentAutoBlur: Bool = true,
                autoBlurKinds: [TargetKind] = Self.defaultAutoBlurKinds) {
        self.neverCapture = neverCapture
        self.agentAutoBlur = agentAutoBlur
        self.autoBlurKinds = autoBlurKinds
    }

    /// The never-capture entry that holds `subject`, if any.
    public func entry(for subject: CaptureSubject) -> NeverCaptureApp? {
        neverCapture.first { $0.matches(subject) }
    }

    public func decision(for subject: CaptureSubject) -> Decision {
        guard let entry = entry(for: subject) else { return .allow }
        return .blackOut(reason: Self.reason(for: entry, subject: subject))
    }

    /// The label on a blacked-out window and the message of a refused capture.
    public static func reason(for entry: NeverCaptureApp, subject: CaptureSubject) -> String {
        "\(subject.appName ?? entry.name) is on the never-capture list"
    }

    /// Adds an app unless an entry already holds it.
    public mutating func add(_ app: NeverCaptureApp) {
        let subject = CaptureSubject(bundleIdentifier: app.bundleIdentifier, appName: app.name)
        guard entry(for: subject) == nil else { return }
        neverCapture.append(app)
    }

    public mutating func remove(_ app: NeverCaptureApp) {
        neverCapture.removeAll { $0 == app }
    }
}
