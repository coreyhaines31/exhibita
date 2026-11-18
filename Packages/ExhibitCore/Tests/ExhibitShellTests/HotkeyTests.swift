import ExhibitShell
import Foundation
import Testing

/// What `defaults read com.apple.symbolichotkeys` returns, as property list values.
struct Entry {
    var enabled: Bool
    var keyCode: Int
    var mask: Int

    init(_ enabled: Bool, _ keyCode: Int, _ mask: Int) {
        self.enabled = enabled
        self.keyCode = keyCode
        self.mask = mask
    }
}

func symbolicHotKeys(_ entries: [Int: Entry]) -> [String: Any] {
    var table: [String: Any] = [:]
    for (id, entry) in entries {
        table[String(id)] = [
            "enabled": NSNumber(value: entry.enabled),
            "value": ["parameters": [NSNumber(value: 52), NSNumber(value: entry.keyCode), NSNumber(value: entry.mask)],
                      "type": "standard"] as [String: Any]
        ] as [String: Any]
    }
    return table
}

let shiftCommand = 0x120000
let controlShiftCommand = 0x160000

@Suite struct KeyComboTests {
    @Test func displaysInMacOSOrder() {
        #expect(KeyCombo(keyCode: 0x15, modifiers: [.shift, .option]).display == "⌥⇧4")
        #expect(KeyCombo(keyCode: 0x15, modifiers: [.command, .shift, .control]).display == "⌃⇧⌘4")
        #expect(KeyCombo(keyCode: 0x31, modifiers: [.command]).display == "⌘Space")
        #expect(KeyCombo(keyCode: 0x7F, modifiers: [.command]).display == "⌘Key 127")
    }

    @Test func dropsModifierBitsItDoesNotKnow() {
        let combo = KeyCombo(keyCode: 0x15, modifiers: KeyModifiers(rawValue: KeyModifiers.command.rawValue | 1 << 23))
        #expect(combo.modifiers == [.command])
    }

    @Test func modifierBitsMatchTheSystemMask() {
        #expect(KeyModifiers([.command, .shift]).rawValue == UInt(shiftCommand))
        #expect(KeyModifiers([.control, .command, .shift]).rawValue == UInt(controlShiftCommand))
    }
}

@Suite struct SystemScreenshotShortcutsTests {
    @Test func missingPreferencesMeanEverythingIsOn() {
        let shortcuts = SystemScreenshotShortcuts(symbolicHotKeys: nil)
        #expect(!shortcuts.wasRead)
        #expect(shortcuts.entries.allSatisfy { $0.isEnabled })
        #expect(!shortcuts.selectionShortcutsAreOff)
        #expect(shortcuts.conflict(with: KeyCombo(keyCode: 0x15, modifiers: [.command, .shift])) == .saveSelection)
    }

    @Test func missingEntriesUseTheFactorySetting() {
        let shortcuts = SystemScreenshotShortcuts(symbolicHotKeys: symbolicHotKeys([30: Entry(false, 21, shiftCommand)]))
        #expect(shortcuts.wasRead)
        #expect(shortcuts.entry(.saveSelection)?.isEnabled == false)
        #expect(shortcuts.entry(.copySelection)?.isEnabled == true)
        #expect(shortcuts.entry(.copySelection)?.combo.display == "⌃⇧⌘4")
        #expect(!shortcuts.selectionShortcutsAreOff)
    }

    @Test func readsBothSelectionShortcutsOff() {
        let shortcuts = SystemScreenshotShortcuts(symbolicHotKeys: symbolicHotKeys([
            30: Entry(false, 21, shiftCommand), 31: Entry(false, 21, controlShiftCommand)
        ]))
        #expect(shortcuts.selectionShortcutsAreOff)
        #expect(shortcuts.conflict(with: KeyCombo(keyCode: 0x15, modifiers: [.command, .shift])) == nil)
        // ⇧⌘3 and ⇧⌘5 are still on.
        #expect(shortcuts.conflict(with: KeyCombo(keyCode: 0x14, modifiers: [.command, .shift])) == .saveScreen)
        #expect(shortcuts.conflict(with: KeyCombo(keyCode: 0x17, modifiers: [.command, .shift])) == .options)
    }

    @Test func readsRemappedSystemKeys() {
        // Someone moved "save selection" to ⌥⇧4: Exhibit A's pre-takeover default now clashes with it.
        let shortcuts = SystemScreenshotShortcuts(symbolicHotKeys: symbolicHotKeys([30: Entry(true, 21, 0xA0000)]))
        #expect(shortcuts.conflict(with: KeyCombo(keyCode: 0x15, modifiers: [.option, .shift])) == .saveSelection)
    }

    @Test func toleratesOddValues() {
        let table: [String: Any] = ["30": ["enabled": 0], "31": "nonsense", "184": ["enabled": true, "value": [:]]]
        let shortcuts = SystemScreenshotShortcuts(symbolicHotKeys: table)
        #expect(shortcuts.entry(.saveSelection)?.isEnabled == false)
        #expect(shortcuts.entry(.saveSelection)?.combo.display == "⇧⌘4")
        #expect(shortcuts.entry(.copySelection)?.isEnabled == true)
        #expect(shortcuts.entry(.options)?.combo.display == "⇧⌘5")
    }
}

@Suite struct HotkeyBindingsTests {
    let off = SystemScreenshotShortcuts(symbolicHotKeys: symbolicHotKeys([
        30: Entry(false, 21, shiftCommand), 31: Entry(false, 21, controlShiftCommand)
    ]))

    @Test func defaultsAvoidTheSystemKeysUntilTakeover() {
        let before = HotkeyBindings()
        #expect(before.combo(for: .captureAndEdit).display == "⌥⇧4")
        #expect(before.combo(for: .captureToClipboard).display == "⌃⌥⇧4")
        #expect(before.takeoverSuggestion == .offer)
        #expect(HotkeyAction.allCases.allSatisfy { before.issue(for: $0) == nil })

        let after = HotkeyBindings(system: off)
        #expect(after.combo(for: .captureAndEdit).display == "⇧⌘4")
        #expect(after.combo(for: .captureToClipboard).display == "⌃⇧⌘4")
        #expect(after.takeoverSuggestion == .done)
        #expect(HotkeyAction.allCases.allSatisfy { after.issue(for: $0) == nil })
    }

    @Test func customKeysStayAfterTakeover() {
        var bindings = HotkeyBindings()
        let custom = KeyCombo(keyCode: 0x08, modifiers: [.control, .option])
        #expect(bindings.assign(custom, to: .captureAndEdit) == nil)
        bindings.system = off
        #expect(bindings.combo(for: .captureAndEdit) == custom)
        #expect(bindings.combo(for: .captureToClipboard).display == "⌃⇧⌘4")
        bindings.reset(.captureAndEdit)
        #expect(bindings.combo(for: .captureAndEdit).display == "⇧⌘4")
    }

    @Test func assigningTheDefaultStoresNothing() {
        var bindings = HotkeyBindings()
        #expect(bindings.assign(HotkeyAction.captureAndEdit.defaultCombo(takenOver: false), to: .captureAndEdit) == nil)
        #expect(!bindings.isCustom(.captureAndEdit))
    }

    @Test func refusesKeysWithoutACommandModifier() {
        var bindings = HotkeyBindings()
        #expect(bindings.assign(KeyCombo(keyCode: 0x15, modifiers: [.shift]), to: .captureAndEdit) == .needsModifier)
        #expect(bindings.assign(KeyCombo(keyCode: 0x15, modifiers: []), to: .captureAndEdit) == .needsModifier)
        #expect(!bindings.isCustom(.captureAndEdit))
    }

    @Test func refusesTheOtherHotkeysKeys() {
        var bindings = HotkeyBindings()
        let clipboard = bindings.combo(for: .captureToClipboard)
        #expect(bindings.assign(clipboard, to: .captureAndEdit) == .usedBy(.captureToClipboard))
    }

    @Test func refusesKeysMacOSStillUses() {
        var bindings = HotkeyBindings()
        let issue = bindings.assign(KeyCombo(keyCode: 0x15, modifiers: [.command, .shift]), to: .captureAndEdit)
        #expect(issue == .takenBySystem(.saveSelection))
        #expect(issue?.message.contains("Keyboard Shortcuts") == true)
    }

    @Test func flagsACustomKeyThatMacOSTakesLater() {
        var bindings = HotkeyBindings(system: off)
        #expect(bindings.assign(KeyCombo(keyCode: 0x15, modifiers: [.command, .shift, .option]), to: .captureAndEdit) == nil)
        bindings.system = SystemScreenshotShortcuts(symbolicHotKeys: symbolicHotKeys([30: Entry(true, 21, 0x1A0000)]))
        #expect(bindings.issue(for: .captureAndEdit) == .takenBySystem(.saveSelection))
    }
}
