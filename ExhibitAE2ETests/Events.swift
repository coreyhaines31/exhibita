import AppKit
import ExhibitCore
import XCTest

/// Synthetic keyboard and mouse events, posted to the app's own windows. In-process events need no
/// Accessibility permission and never reach another app.
@MainActor
enum Events {
    /// ANSI virtual key codes for the keys the tests press.
    static let keyCodes: [Character: UInt16] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12, "w": 13,
        "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "9": 25, "7": 26,
        "8": 28, "0": 29, "o": 31, "u": 32, "i": 34, "p": 35, "l": 37, "j": 38, "k": 40, ",": 43, "/": 44, "n": 45,
        "m": 46, ".": 47, " ": 49, "$": 21
    ]
    static let returnKey: UInt16 = 0x24
    static let escape: UInt16 = 0x35
    static let delete: UInt16 = 0x33

    private static var eventNumber = 0

    /// Presses and releases one key through `NSApp.sendEvent`, the way a keyboard press arrives: key
    /// equivalents first, then the key window's first responder.
    static func key(_ character: Character, _ modifiers: NSEvent.ModifierFlags = [], in window: NSWindow) {
        let lower = Character(character.lowercased())
        let code = keyCodes[lower] ?? 0
        var typed = String(character)
        if modifiers.contains(.shift), character.isLetter { typed = typed.uppercased() }
        if modifiers.contains(.shift), character == "/" { typed = "?" }
        post(code: code, characters: typed, ignoringModifiers: String(lower), modifiers: modifiers, in: window)
    }

    static func special(_ code: UInt16, _ modifiers: NSEvent.ModifierFlags = [], in window: NSWindow) {
        let characters: String
        switch code {
        case returnKey: characters = "\r"
        case escape: characters = "\u{1b}"
        case delete: characters = "\u{7f}"
        default: characters = ""
        }
        post(code: code, characters: characters, ignoringModifiers: characters, modifiers: modifiers, in: window)
    }

    /// Types text one key at a time, shifting capitals.
    static func type(_ text: String, in window: NSWindow) {
        for character in text {
            let shifted = character.isUppercase || character == "$"
            post(code: keyCodes[Character(character.lowercased())] ?? 0, characters: String(character),
                 ignoringModifiers: String(character).lowercased(), modifiers: shifted ? [.shift] : [], in: window)
        }
    }

    private static func post(code: UInt16, characters: String, ignoringModifiers: String,
                             modifiers: NSEvent.ModifierFlags, in window: NSWindow) {
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            guard let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: modifiers,
                                               timestamp: ProcessInfo.processInfo.systemUptime,
                                               windowNumber: window.windowNumber, context: nil,
                                               characters: characters, charactersIgnoringModifiers: ignoringModifiers,
                                               isARepeat: false, keyCode: code) else {
                XCTFail("Couldn't make a key event")
                return
            }
            NSApp.sendEvent(event)
        }
    }

    // MARK: - Mouse

    static func click(at point: NSPoint, in window: NSWindow, count: Int = 1) {
        for click in 1...count {
            mouse(.leftMouseDown, at: point, in: window, clickCount: click)
            mouse(.leftMouseUp, at: point, in: window, clickCount: click)
        }
    }

    /// Down at `from`, a few drags along the way, up at `to`.
    static func drag(from: NSPoint, to: NSPoint, in window: NSWindow, steps: Int = 8) {
        mouse(.leftMouseDown, at: from, in: window)
        for step in 1...steps {
            let t = CGFloat(step) / CGFloat(steps)
            mouse(.leftMouseDragged, at: NSPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t),
                  in: window)
        }
        mouse(.leftMouseUp, at: to, in: window)
    }

    static func mouse(_ type: NSEvent.EventType, at point: NSPoint, in window: NSWindow, clickCount: Int = 1) {
        eventNumber += 1
        guard let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                                             timestamp: ProcessInfo.processInfo.systemUptime,
                                             windowNumber: window.windowNumber, context: nil,
                                             eventNumber: eventNumber, clickCount: clickCount,
                                             pressure: type == .leftMouseUp ? 0 : 1) else {
            XCTFail("Couldn't make a mouse event")
            return
        }
        window.sendEvent(event)
    }
}

/// Where things are on screen, found through the real views' accessibility elements (in process, no permission).
@MainActor
enum Locate {
    /// Every accessibility element under `root`, depth first.
    static func elements(under root: Any) -> [NSObject & NSAccessibilityProtocol] {
        var found: [NSObject & NSAccessibilityProtocol] = []
        var queue: [Any] = [root]
        var seen = 0
        while let next = queue.popLast(), seen < 5000 {
            seen += 1
            guard let element = next as? NSObject & NSAccessibilityProtocol else { continue }
            found.append(element)
            if let children = element.accessibilityChildren() { queue.append(contentsOf: children) }
        }
        return found
    }

    /// The frame, in window coordinates, of the first element whose label matches.
    static func frame(labelled match: (String) -> Bool, in window: NSWindow) -> NSRect? {
        frames(labelled: match, in: window).first
    }

    static func frames(labelled match: (String) -> Bool, in window: NSWindow) -> [NSRect] {
        guard let root = window.contentView else { return [] }
        return elements(under: root).compactMap { element in
            guard let label = element.accessibilityLabel(), match(label) else { return nil }
            return window.convertFromScreen(element.accessibilityFrame())
        }
    }

    /// Every label under the window, for failure messages.
    static func labels(in window: NSWindow) -> [String] {
        guard let root = window.contentView else { return [] }
        return elements(under: root).compactMap { $0.accessibilityLabel() }.filter { !$0.isEmpty }
    }
}

/// Image pixels (top-left origin) to window points, through the canvas the editor actually laid out.
@MainActor
struct CanvasMap {
    let frame: NSRect
    let pixelSize: CGSize

    init(window: NSWindow, pixelSize: CGSize) throws {
        frame = try XCTUnwrap(Locate.frame(labelled: { $0 == "Capture" }, in: window),
                              "the editor canvas's accessibility element")
        self.pixelSize = pixelSize
    }

    var pointsPerPixel: CGFloat { frame.width / pixelSize.width }

    func point(_ pixel: PixelPoint) -> NSPoint {
        NSPoint(x: frame.minX + pixel.x * pointsPerPixel, y: frame.maxY - pixel.y * pointsPerPixel)
    }

    func point(_ rect: PixelRect) -> NSPoint {
        point(PixelPoint(x: rect.midX, y: rect.midY))
    }
}
