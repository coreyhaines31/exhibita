import SwiftUI

/// Names and colours in one place.
enum Brand {
    static let name = "Exhibit A"
    static let bundleIdentifier = "com.exhibitaformac.ExhibitA"
    /// The pilot light colour. mac-app-kit assigns each app's accent with its icon; until then this olive sits
    /// clear of the status hues and the other apps' accents.
    static let accent = Color(red: 0x6E / 255, green: 0x8B / 255, blue: 0x1E / 255)
}
