import CoreGraphics
import Foundation

/// A window on screen, as the window list reports it: frame in Core Graphics global coordinates (origin at the
/// main display's top-left, y down).
public struct WindowCandidate: Equatable, Sendable {
    public var id: UInt32
    public var frame: CGRect
    /// 0 is ordinary app windows; menus, the Dock and overlays sit on other layers.
    public var layer: Int
    public var ownerPID: Int32
    public var ownerName: String?
    public var title: String?
    public var bundleIdentifier: String?

    public init(id: UInt32, frame: CGRect, layer: Int, ownerPID: Int32, ownerName: String? = nil,
                title: String? = nil, bundleIdentifier: String? = nil) {
        self.id = id
        self.frame = frame
        self.layer = layer
        self.ownerPID = ownerPID
        self.ownerName = ownerName
        self.title = title
        self.bundleIdentifier = bundleIdentifier
    }
}

/// Space then click: the window under the pointer.
public enum WindowPicker {
    /// Windows smaller than this on either side (status items, invisible helpers) are never picked.
    public static let minimumSide: CGFloat = 40

    /// The frontmost ordinary window under `point`. `windows` must be front to back, as
    /// `CGWindowListCopyWindowInfo(.optionOnScreenOnly)` returns them. Windows of `excludingPID`, when given,
    /// are skipped.
    public static func pick(at point: CGPoint, in windows: [WindowCandidate],
                            excludingPID: Int32? = nil) -> WindowCandidate? {
        windows.first { window in
            window.layer == 0 && window.ownerPID != excludingPID
                && window.frame.width >= minimumSide && window.frame.height >= minimumSide
                && window.frame.contains(point)
        }
    }
}
