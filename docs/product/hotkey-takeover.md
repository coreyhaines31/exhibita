# Taking over ⇧⌘4

Unit 4, 2026-11-18. The question from the spec: can Exhibit A turn off macOS's own screenshot shortcuts itself, or can it only link to the setting? Nothing here was tried on a real Mac: changing this Mac's system settings was out of bounds for the unit, so every "works" below is from documentation, the format of the preferences file, and how other tools are reported to behave. The live checks are in `unit4-live-checklist.md`.

## Decision

Exhibit A **reads** the screenshot shortcuts and **links** to System Settings. It does not write them.

- Before takeover the hotkeys are ⌥⇧4 (capture and edit) and ⌃⌥⇧4 (capture to clipboard), so they never fight macOS for a key.
- The empty panel and Settings offer "Open Keyboard Settings…". The person turns off the shortcuts under Keyboard Shortcuts, Screenshots.
- When both selection shortcuts (ids 30 and 31) read as off, the defaults move to ⇧⌘4 and ⌃⇧⌘4 by themselves. A key the person picked stays as picked.
- A key macOS still uses is refused in Settings with the name of the system shortcut that holds it (`HotkeyBindings.issue`).

## Where the shortcuts live

`~/Library/Preferences/com.apple.symbolichotkeys.plist`, key `AppleSymbolicHotKeys`, a dictionary keyed by id as a string:

| Id | Shortcut | Factory keys |
|---|---|---|
| 28 | Save picture of screen as a file | ⇧⌘3 |
| 29 | Copy picture of screen to the clipboard | ⌃⇧⌘3 |
| 30 | Save picture of selected area as a file | ⇧⌘4 |
| 31 | Copy picture of selected area to the clipboard | ⌃⇧⌘4 |
| 184 | Screenshot and recording options | ⇧⌘5 |

Each entry is `{enabled = 0 or 1; value = {parameters = (character, virtual key code, modifier mask); type = standard;};}`. ⇧⌘4 is `(52, 21, 1179648)`: `"4"`, `kVK_ANSI_4`, shift plus command in `NSEvent.ModifierFlags` bits. An id with no entry has never been changed and is on at its factory keys. `SystemScreenshotShortcuts` in `ExhibitShell` parses this, with tests for missing entries, remapped keys and malformed values.

## Detection (built)

`SystemShortcuts.read()` calls `CFPreferencesAppSynchronize` and then `CFPreferencesCopyAppValue("AppleSymbolicHotKeys", "com.apple.symbolichotkeys")`. Exhibit A is not sandboxed (Developer ID, hardened runtime, as its siblings), so reading another domain needs no entitlement. A sandboxed build would need `com.apple.security.temporary-exception.shared-preference.read-only` for that domain.

It reads again when the panel opens, when Settings comes forward and when a hotkey fires. There is no polling (the idle budget is 0% CPU), and no documented notification for this domain changing, so a change made in System Settings shows up the next time one of those happens.

## Writing the setting (not built)

Possible ways an app could turn the shortcuts off itself:

1. **Write the preferences.** `CFPreferencesSetAppValue` (or `defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 30 '{enabled = 0; ...}'`) persists the change. On its own it is not picked up by the running session: the shortcut keeps working until logout. Running the private `/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u` is widely reported to apply it without logout, but it is undocumented and its behaviour across macOS 14, 15 and 26 is unverified.
2. **Private SkyLight call.** `CGSSetSymbolicHotKeyEnabled` turns a symbolic hot key off for the current session at once, without persisting. It is private API that can change in any release.

Sandbox and notarization:

- A sandboxed app cannot write another app's preferences domain; the only route is a temporary-exception entitlement, which App Store review rejects. Exhibit A ships outside the App Store, unsandboxed, so this does not block it.
- Notarization checks the signature, hardened runtime and malware scan. It does not review behaviour or private API use, so neither route would fail notarization. Hardened runtime does not restrict writing preferences.

Why not do it anyway:

- **Uninstall leaves the Mac changed.** A dragged-to-Trash app cannot run code to restore the setting, so someone who removes Exhibit A would be left with no ⇧⌘4 and no idea why.
- **Silent system changes cost trust.** The Trust section promises nothing changes behind the person's back. Two clicks in System Settings, done by the person, is the honest version.
- **Fragility.** Both live-apply routes are undocumented. If a macOS update breaks one, the takeover fails quietly and both apps fight for the key.

If this is revisited, the least bad version is an explicit button ("Turn off macOS's screenshot shortcuts") that writes ids 30 and 31 (and only those), runs `activateSettings -u`, re-reads to confirm, and has a matching "Turn them back on" in Settings and in the uninstall notes.

## Deep link

`x-apple.systempreferences:com.apple.Keyboard-Settings.extension` opens System Settings, Keyboard (macOS 13 and later). Screenshots sits behind its Keyboard Shortcuts… button; no public anchor for that sheet is known, so the copy names the two clicks. Screen Recording uses `x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture`.

## Not verified

- That the deep link opens Keyboard on macOS 14, 15 and 26.
- That `CFPreferencesAppSynchronize` picks up a change System Settings just made, without relaunching Exhibit A.
- That turning the shortcuts off in System Settings frees ⇧⌘4 for `RegisterEventHotKey` at once, without logout.
- Everything in "Writing the setting".
