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

/// What may be captured. Every capture, by a person or an agent, asks this one place. The never-capture list
/// (unit 6) lands here; for now everything is allowed.
public struct CapturePolicy: Equatable, Sendable {
    public enum Decision: Equatable, Sendable {
        case allow
        /// Black out the subject's windows, with the reason shown on the label.
        case blackOut(reason: String)
    }

    public init() {}

    public func decision(for subject: CaptureSubject) -> Decision {
        .allow
    }
}
