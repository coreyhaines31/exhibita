import CoreGraphics
import Foundation

/// The capture bridge: the CLI asks the running app, which holds the Screen Recording grant, for live captures.
/// One request and one response per connection, each a single line of JSON. Reference:
/// `docs/product/capture-bridge.md`.
public enum BridgeProtocol {
    /// Bumped when a request or response changes incompatibly. Both sides refuse other versions.
    public static let version = 1
    /// The longest line either side reads. Requests are tiny; responses carry paths and counts, never pixels.
    public static let maxLineBytes = 1 << 20
}

public struct BridgeRequest: Codable, Equatable, Sendable {
    public enum Method: String, Codable, Sendable {
        case ping, capture, open
    }

    public var v: Int
    public var id: String
    /// Kept as a string so an unknown method gets a clear error instead of an undecodable request.
    public var method: String
    public var capture: CaptureParameters?
    public var open: OpenParameters?

    public init(id: String = UUID().uuidString, method: Method, capture: CaptureParameters? = nil,
                open: OpenParameters? = nil, version: Int = BridgeProtocol.version) {
        v = version
        self.id = id
        self.method = method.rawValue
        self.capture = capture
        self.open = open
    }
}

/// A rect in points, top-left origin, local to a display.
public struct BridgeRect: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}

/// `exhibit capture` options. With none, the whole main display.
public struct CaptureParameters: Codable, Equatable, Sendable {
    /// An app name, bundle identifier or window title (`WindowQuery`).
    public var window: String?
    /// 1 is the main display (the one with the menu bar); the rest follow in macOS's order.
    public var display: Int?
    /// Points on the display, top-left origin.
    public var region: BridgeRect?

    public init(window: String? = nil, display: Int? = nil, region: BridgeRect? = nil) {
        self.window = window
        self.display = display
        self.region = region
    }

    /// What to capture, or why the parameters do not make sense.
    public func target() throws -> CaptureTarget {
        if let window {
            guard display == nil, region == nil else {
                throw BridgeError(.badRequest, "--window cannot be combined with --display, --screen or --region.")
            }
            guard !window.trimmingCharacters(in: .whitespaces).isEmpty else {
                throw BridgeError(.badRequest, "--window needs an app name or a window title.")
            }
            return .window(window)
        }
        let display = display ?? 1
        guard display >= 1 else { throw BridgeError(.badRequest, "--display counts from 1, the main display.") }
        if let region {
            guard [region.x, region.y, region.width, region.height].allSatisfy(\.isFinite), region.width > 0,
                  region.height > 0 else {
                throw BridgeError(.badRequest, "--region takes x,y,w,h in points with a positive width and height.")
            }
        }
        return .display(display, region: region?.cgRect)
    }
}

/// What a capture request resolves to.
public enum CaptureTarget: Equatable, Sendable {
    case window(String)
    /// A display, counted from 1, and optionally a region of it in points (top-left origin).
    case display(Int, region: CGRect?)
}

public struct OpenParameters: Codable, Equatable, Sendable {
    public var captureID: UUID

    public init(captureID: UUID) {
        self.captureID = captureID
    }
}

public struct BridgeResponse: Codable, Equatable, Sendable {
    public var v: Int
    public var id: String
    public var capture: CaptureResult?
    public var open: OpenResult?
    public var pong: Bool?
    public var error: BridgeError?

    public init(id: String, capture: CaptureResult? = nil, open: OpenResult? = nil, pong: Bool? = nil,
                error: BridgeError? = nil) {
        v = BridgeProtocol.version
        self.id = id
        self.capture = capture
        self.open = open
        self.pong = pong
        self.error = error
    }
}

/// What an agent gets back from a capture. `image` is the copy for the agent: detected secrets blurred unless
/// auto-blur is off. `bundle` holds the untouched original for the person.
public struct CaptureResult: Codable, Equatable, Sendable {
    public struct AutoBlur: Codable, Equatable, Sendable {
        public var enabled: Bool
        /// How many targets were blurred in `image`.
        public var blurred: Int
        /// Blurred targets by kind, like `{"email": 2}`.
        public var kinds: [String: Int]

        public init(enabled: Bool, blurred: Int, kinds: [String: Int]) {
            self.enabled = enabled
            self.blurred = blurred
            self.kinds = kinds
        }
    }

    public var id: UUID
    public var bundle: String
    public var image: String
    public var width: Int
    public var height: Int
    public var scale: Double
    public var appName: String?
    public var windowTitle: String?
    public var autoBlur: AutoBlur
    /// One reason per never-capture window drawn black in the image.
    public var blackedOut: [String]
    public var targets: Int

    public init(id: UUID, bundle: String, image: String, width: Int, height: Int, scale: Double, appName: String?,
                windowTitle: String?, autoBlur: AutoBlur, blackedOut: [String], targets: Int) {
        self.id = id
        self.bundle = bundle
        self.image = image
        self.width = width
        self.height = height
        self.scale = scale
        self.appName = appName
        self.windowTitle = windowTitle
        self.autoBlur = autoBlur
        self.blackedOut = blackedOut
        self.targets = targets
    }
}

public struct OpenResult: Codable, Equatable, Sendable {
    public var id: UUID
    public var shown: Bool

    public init(id: UUID, shown: Bool) {
        self.id = id
        self.shown = shown
    }
}

/// A window an ambiguous `--window` could mean.
public struct WindowSummary: Codable, Equatable, Sendable {
    public var app: String?
    public var title: String?
    public var bundleIdentifier: String?

    public init(app: String?, title: String?, bundleIdentifier: String?) {
        self.app = app
        self.title = title
        self.bundleIdentifier = bundleIdentifier
    }
}

/// A failure the app reports, with a stable `code` the CLI maps to an exit status (`docs/cli.md`).
public struct BridgeError: Error, Codable, Equatable, Sendable, CustomStringConvertible {
    public enum Code: String, Codable, Sendable, CaseIterable {
        case permissionNotGranted = "permission_not_granted"
        case windowNotFound = "window_not_found"
        case ambiguousWindow = "ambiguous_window"
        case neverCapture = "never_capture"
        case displayNotFound = "display_not_found"
        case unknownCapture = "unknown_capture"
        case captureFailed = "capture_failed"
        case badRequest = "bad_request"
        case unsupportedVersion = "unsupported_version"
        case unknownMethod = "unknown_method"
    }

    /// The code as sent. Kept as a string so a newer app's codes still reach the CLI.
    public var code: String
    public var message: String
    public var candidates: [WindowSummary]?

    public init(_ code: Code, _ message: String, candidates: [WindowSummary]? = nil) {
        self.code = code.rawValue
        self.message = message
        self.candidates = candidates
    }

    public var description: String { "\(code): \(message)" }
}

enum BridgeJSON {
    static func encodeLine(_ value: some Encodable) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(value)
        data.append(0x0A)
        return data
    }

    static func decode<T: Decodable>(_ type: T.Type, from line: Data) throws -> T {
        try JSONDecoder().decode(type, from: line)
    }
}
