import CoreGraphics
import ExhibitShell
import Foundation
@preconcurrency import ScreenCaptureKit

/// A finished capture, before it is saved.
struct CapturedImage: @unchecked Sendable {
    var image: CGImage
    var scale: Double
    var appName: String?
    var windowTitle: String?
    /// The display it came from, so the editor opens there.
    var displayID: CGDirectDisplayID?
}

enum CaptureFailure: Error {
    case displayGone
    case windowGone
}

/// One still image through ScreenCaptureKit. Exhibit A's own windows (the overlay, the panel) are always left
/// out. Call only once Screen Recording is granted: asking for shareable content without it prompts.
enum ScreenCapturer {
    static func capture(_ region: CaptureRegion) async throws -> CapturedImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == region.displayID }) else {
            throw CaptureFailure.displayGone
        }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let own = content.applications.filter { $0.processID == ownPID }
        let filter = SCContentFilter(display: display, excludingApplications: own, exceptingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = region.sourceRect
        configuration.width = region.pixelSize.width
        configuration.height = region.pixelSize.height
        configuration.showsCursor = false
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        return CapturedImage(image: image, scale: region.scale, displayID: region.displayID)
    }

    static func capture(windowID: UInt32) async throws -> CapturedImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
            throw CaptureFailure.windowGone
        }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let scale = Double(filter.pointPixelScale)
        let configuration = SCStreamConfiguration()
        configuration.width = Int((filter.contentRect.width * scale).rounded())
        configuration.height = Int((filter.contentRect.height * scale).rounded())
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = true
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        var display: CGDirectDisplayID = 0
        var matching: UInt32 = 0
        let center = CGPoint(x: window.frame.midX, y: window.frame.midY)
        let found = CGGetDisplaysWithPoint(center, 1, &display, &matching) == .success && matching >= 1
        return CapturedImage(image: image, scale: scale, appName: window.owningApplication?.applicationName,
                             windowTitle: window.title, displayID: found ? display : nil)
    }
}

/// On-screen windows, front to back, for Space-to-pick.
enum WindowList {
    static func onScreen() -> [WindowCandidate] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        return info.compactMap { entry in
            guard let number = entry[kCGWindowNumber as String] as? Int,
                  let bounds = entry[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  let pid = entry[kCGWindowOwnerPID as String] as? Int32
            else { return nil }
            return WindowCandidate(id: UInt32(number), frame: frame, layer: entry[kCGWindowLayer as String] as? Int ?? 0,
                                   ownerPID: pid, ownerName: entry[kCGWindowOwnerName as String] as? String,
                                   title: entry[kCGWindowName as String] as? String)
        }
    }
}
