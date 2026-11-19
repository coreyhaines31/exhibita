import CoreGraphics
import ExhibitCore
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
    /// One reason per never-capture window left out and drawn black.
    var blackedOut: [String] = []
}

enum CaptureFailure: Error {
    case displayGone
    case windowGone
    case outsideStill
}

/// One display as it was when the hotkey fired: the whole display, Exhibit A's own windows included, with
/// never-capture windows left out and drawn black (`Blackout`).
struct DisplayStill: @unchecked Sendable {
    /// The display in global Cocoa points, as the overlay and `SelectionGeometry` see it.
    var display: DisplayGeometry
    var image: CGImage
    var blackout: [Blackout.Region]

    var pixelSize: PixelSize { PixelSize(width: image.width, height: image.height) }
}

/// Every display at the hotkey, and the windows on them front to back (Core Graphics global points), so the
/// overlay can show the screen frozen and every selection is cut out of what was there.
struct FrozenScreen: @unchecked Sendable {
    var stills: [DisplayStill]
    var windows: [WindowCandidate]
    var mainDisplayHeight: CGFloat

    var displays: [DisplayGeometry] { stills.map(\.display) }

    func still(for displayID: UInt32) -> DisplayStill? {
        stills.first { $0.display.id == displayID }
    }
}

/// Still images through ScreenCaptureKit. People's captures freeze every display at the hotkey (`freeze`) and
/// are cut out of those stills (`cut`), so they show exactly what was on screen, Exhibit A's own editor and
/// panel included. Agent captures (`capture(_:policy:)`, `capture(windowID:)`) are taken live and leave Exhibit
/// A's own windows out. Never-capture apps are left out of both, their area drawn black with a label
/// (`Blackout`). Call only once Screen Recording is granted: asking for shareable content without it prompts.
/// Nothing here activates an app or moves focus.
enum ScreenCapturer {
    /// Every display in `displays`, at its own scale. `windows` is the window list taken at the same moment.
    static func freeze(_ displays: [DisplayGeometry], windows: [WindowCandidate], mainDisplayHeight: CGFloat,
                       policy: CapturePolicy) async throws -> FrozenScreen {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let listed = content.applications.filter { policy.entry(for: subject(of: $0)) != nil }
        let listedWindows = neverCaptureWindows(in: content, policy: policy)
        let jobs = try displays.map { geometry -> StillJob in
            guard let display = content.displays.first(where: { $0.displayID == geometry.id }) else {
                throw CaptureFailure.displayGone
            }
            return StillJob(display: display, geometry: geometry, listed: listed, listedWindows: listedWindows,
                            policy: policy)
        }
        // All displays at once, so the stills are as close to the same moment as ScreenCaptureKit allows.
        let stills = try await withThrowingTaskGroup(of: DisplayStill.self) { group in
            for job in jobs {
                group.addTask { try await still(job) }
            }
            var stills: [DisplayStill] = []
            for try await still in group { stills.append(still) }
            return stills
        }
        let order = displays.map(\.id)
        return FrozenScreen(stills: stills.sorted { order.firstIndex(of: $0.display.id) ?? 0
                                                    < order.firstIndex(of: $1.display.id) ?? 0 },
                            windows: windows, mainDisplayHeight: mainDisplayHeight)
    }

    /// One display's still, with what it needs from the shared content. ScreenCaptureKit's objects are not
    /// `Sendable`; each job is only read, by one task.
    private struct StillJob: @unchecked Sendable {
        var display: SCDisplay
        var geometry: DisplayGeometry
        var listed: [SCRunningApplication]
        var listedWindows: [WindowCandidate]
        var policy: CapturePolicy
    }

    private static func still(_ job: StillJob) async throws -> DisplayStill {
        let (display, geometry, policy) = (job.display, job.geometry, job.policy)
        let filter = SCContentFilter(display: display, excludingApplications: job.listed, exceptingWindows: [])
        let whole = SelectionGeometry.fullScreen(geometry)
        let configuration = SCStreamConfiguration()
        configuration.width = whole.pixelSize.width
        configuration.height = whole.pixelSize.height
        configuration.showsCursor = false
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        let regions = Blackout.regions(windows: job.listedWindows, policy: policy, captureRect: display.frame,
                                       pixelSize: PixelSize(width: image.width, height: image.height))
        let painted = try Blackout.paint(image, regions: regions, scale: geometry.scale)
        return DisplayStill(display: geometry, image: painted, blackout: regions)
    }

    /// `region` cut out of its display's still, as a capture of its own (a copy, so the whole still is not kept
    /// alive by it).
    static func cut(_ region: CaptureRegion, from frozen: FrozenScreen, appName: String? = nil,
                    windowTitle: String? = nil) throws -> CapturedImage {
        guard let still = frozen.still(for: region.displayID) else { throw CaptureFailure.displayGone }
        guard let pixels = SelectionGeometry.stillPixels(of: region, on: still.display, stillSize: still.pixelSize)
        else { throw CaptureFailure.outsideStill }
        let rect = CGRect(x: pixels.x, y: pixels.y, width: pixels.width, height: pixels.height)
        guard let cropped = still.image.cropping(to: rect) else { throw CaptureFailure.outsideStill }
        let space = still.image.colorSpace.flatMap { $0.model == .rgb && $0.supportsOutput ? $0 : nil }
            ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(data: nil, width: cropped.width, height: cropped.height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw ExhibitError.renderFailed
        }
        context.interpolationQuality = .none
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: cropped.width, height: cropped.height))
        guard let image = context.makeImage() else { throw ExhibitError.renderFailed }
        let reasons = still.blackout.filter { region in
            CGRect(x: region.rect.x, y: region.rect.y, width: region.rect.width, height: region.rect.height)
                .intersects(rect)
        }.map(\.reason)
        return CapturedImage(image: image, scale: region.scale, appName: appName, windowTitle: windowTitle,
                             displayID: region.displayID, blackedOut: reasons)
    }

    /// Never-capture apps' windows, in ScreenCaptureKit's global top-left points.
    private static func neverCaptureWindows(in content: SCShareableContent, policy: CapturePolicy) -> [WindowCandidate] {
        content.windows.compactMap { window -> WindowCandidate? in
            guard let app = window.owningApplication, policy.entry(for: subject(of: app)) != nil else { return nil }
            return WindowCandidate(id: window.windowID, frame: window.frame, layer: window.windowLayer,
                                   ownerPID: app.processID, ownerName: app.applicationName,
                                   bundleIdentifier: app.bundleIdentifier)
        }
    }

    /// A live capture for an agent, Exhibit A's own windows left out.
    static func capture(_ region: CaptureRegion, policy: CapturePolicy) async throws -> CapturedImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == region.displayID }) else {
            throw CaptureFailure.displayGone
        }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let own = content.applications.filter { $0.processID == ownPID }
        let listed = content.applications.filter { policy.entry(for: subject(of: $0)) != nil }
        let filter = SCContentFilter(display: display, excludingApplications: own + listed, exceptingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = region.sourceRect
        configuration.width = region.pixelSize.width
        configuration.height = region.pixelSize.height
        configuration.showsCursor = false
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        // Window and display frames share one global top-left point space.
        let captureRect = region.sourceRect.offsetBy(dx: display.frame.minX, dy: display.frame.minY)
        let listedWindows = neverCaptureWindows(in: content, policy: policy)
        let regions = Blackout.regions(windows: listedWindows, policy: policy, captureRect: captureRect,
                                       pixelSize: PixelSize(width: image.width, height: image.height))
        let painted = try Blackout.paint(image, regions: regions, scale: region.scale)
        return CapturedImage(image: painted, scale: region.scale, displayID: region.displayID,
                             blackedOut: regions.map(\.reason))
    }

    static func subject(of app: SCRunningApplication) -> CaptureSubject {
        CaptureSubject(bundleIdentifier: app.bundleIdentifier, appName: app.applicationName)
    }

    /// A live capture of one window for an agent (`exhibit capture --window`).
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
