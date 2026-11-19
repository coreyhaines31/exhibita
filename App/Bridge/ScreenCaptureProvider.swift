import AppKit
import ExhibitBridge
import ExhibitShell
@preconcurrency import ScreenCaptureKit

/// Agent captures through ScreenCaptureKit. No overlay, no activation, no focus change, and never a permission
/// prompt: without Screen Recording it refuses instead of asking. The decisions (which window a name means, what
/// is blacked out) are `WindowQuery` and `Blackout` in the package; this only gathers what macOS reports.
struct ScreenCaptureProvider: CaptureProvider {
    func capture(_ target: CaptureTarget, policy: CapturePolicy) async throws -> ProvidedCapture {
        // Asking ScreenCaptureKit for content without the grant would prompt, so check first.
        guard ScreenRecording.isGranted else {
            throw BridgeError(.permissionNotGranted, "Exhibit A does not have Screen Recording. The person turns it "
                              + "on in System Settings, Privacy & Security, Screen & System Audio Recording.")
        }
        let captured: CapturedImage
        do {
            switch target {
            case .window(let query):
                captured = try await captureWindow(query, policy: policy)
            case let .display(number, region):
                captured = try await captureDisplay(number, region: region, policy: policy)
            }
        } catch let error as BridgeError {
            throw error
        } catch CaptureFailure.displayGone {
            throw BridgeError(.displayNotFound, "The display went away during the capture.")
        } catch CaptureFailure.windowGone {
            throw BridgeError(.windowNotFound, "The window closed or left the screen during the capture.")
        } catch {
            throw BridgeError(.captureFailed, "ScreenCaptureKit could not take the capture: "
                              + error.localizedDescription)
        }
        return ProvidedCapture(image: captured.image, scale: captured.scale, appName: captured.appName,
                               windowTitle: captured.windowTitle, blackedOut: captured.blackedOut)
    }

    private func captureWindow(_ query: String, policy: CapturePolicy) async throws -> CapturedImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let windows = Self.frontToBack(content)
        let ownPID = ProcessInfo.processInfo.processIdentifier
        switch WindowQuery.match(query, in: windows, excludingPID: ownPID) {
        case .notFound:
            throw BridgeError(.windowNotFound, "No window matches \"\(query)\". Use an app name, a bundle "
                              + "identifier or part of a window title.")
        case .ambiguous(let candidates):
            throw BridgeError(.ambiguousWindow, "\"\(query)\" matches \(candidates.count) windows. Pass more of "
                              + "the title, or the app's bundle identifier.",
                              candidates: candidates.map { Self.summary($0, policy: policy) })
        case .found(let window):
            let subject = CaptureSubject(bundleIdentifier: window.bundleIdentifier, appName: window.ownerName)
            if case .blackOut(let reason) = policy.decision(for: subject) {
                throw BridgeError(.neverCapture, "\(reason), so it is never captured. The person can change the "
                                  + "list in Exhibit A's Settings.")
            }
            return try await ScreenCapturer.capture(windowID: window.id)
        }
    }

    private func captureDisplay(_ number: Int, region: CGRect?, policy: CapturePolicy) async throws -> CapturedImage {
        // NSScreen.screens starts with the main display, the one with the menu bar.
        let displays = await MainActor.run {
            NSScreen.screens.compactMap { screen -> DisplayGeometry? in
                let key = NSDeviceDescriptionKey("NSScreenNumber")
                guard let id = (screen.deviceDescription[key] as? NSNumber)?.uint32Value else { return nil }
                return DisplayGeometry(id: id, frame: screen.frame, scale: screen.backingScaleFactor)
            }
        }
        guard displays.indices.contains(number - 1) else {
            throw BridgeError(.displayNotFound, "There is no display \(number); this Mac has \(displays.count).")
        }
        let display = displays[number - 1]
        let captureRegion: CaptureRegion
        if let region {
            guard let local = SelectionGeometry.region(local: region, on: display) else {
                throw BridgeError(.badRequest, "--region is outside display \(number), which is "
                                  + "\(Int(display.frame.width)) by \(Int(display.frame.height)) points.")
            }
            captureRegion = local
        } else {
            captureRegion = SelectionGeometry.fullScreen(display)
        }
        return try await ScreenCapturer.capture(captureRegion, policy: policy)
    }

    /// ScreenCaptureKit's windows in the window server's front-to-back order, with bundle identifiers.
    private static func frontToBack(_ content: SCShareableContent) -> [WindowCandidate] {
        let byID = Dictionary(content.windows.map { ($0.windowID, $0) }, uniquingKeysWith: { first, _ in first })
        return WindowList.onScreen().compactMap { listed in
            guard let window = byID[listed.id] else { return nil }
            var candidate = listed
            candidate.frame = window.frame
            candidate.ownerName = window.owningApplication?.applicationName ?? listed.ownerName
            candidate.title = window.title ?? listed.title
            candidate.bundleIdentifier = window.owningApplication?.bundleIdentifier
            return candidate
        }
    }

    /// A never-capture window's title is not passed on, even in an error.
    private static func summary(_ window: WindowCandidate, policy: CapturePolicy) -> WindowSummary {
        let subject = CaptureSubject(bundleIdentifier: window.bundleIdentifier, appName: window.ownerName)
        let listed = policy.entry(for: subject) != nil
        return WindowSummary(app: window.ownerName, title: listed ? nil : window.title,
                             bundleIdentifier: window.bundleIdentifier)
    }
}
