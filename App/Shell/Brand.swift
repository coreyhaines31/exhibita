import SwiftUI

/// Names and colours in one place.
enum Brand {
    static let name = "Exhibit A"
    static let bundleIdentifier = "com.exhibitaformac.ExhibitA"
    /// The pilot light colour, forensic UV purple `#b42ee8`: mac-app-kit's accent for Exhibit A, used only in lights.
    static let accent = Color(red: 0xB4 / 255, green: 0x2E / 255, blue: 0xE8 / 255)
}
