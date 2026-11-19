# Unit 4 live checklist

Everything in unit 4 that only a person at a Mac can check. Unit tests, lint, the Debug build and the offscreen renders in `docs/samples/app` passed; nothing below has been run. Unit 4 is accepted when the first-use journey works on a clean user account and the denial path is shown.

Build: `xcodegen generate`, then `xcodebuild -project ExhibitA.xcodeproj -scheme ExhibitA -configuration Debug -derivedDataPath build/DerivedData build`. A signed build is needed for a stable Screen Recording grant; an unsigned or ad hoc build may be asked again after each rebuild. Use a fresh macOS user account for sections 1 to 3.

Mark each line pass or fail with the macOS version.

## 1. First launch

| Step | Expected |
|---|---|
| Open Exhibit A.app | The exhibit plate glyph (a window outline and a circled A) appears in the menu bar. No Dock icon, no window, no system prompt. |
| Click the glyph | Panel: "Exhibit A needs Screen Recording", with Allow Screen Recording… and Check Again. Pilot light unlit. |
| `ls ~/Library/Application\ Support/Exhibit\ A/Captures` | Exists, holds only `.metadata_never_index`. |
| `tmutil isexcluded ~/Library/Application\ Support/Exhibit\ A/Captures` | `[Excluded]`. |
| Release build only: System Settings, General, Login Items | Exhibit A is listed and on. A Debug build must not appear there. |

## 2. Permission and the denial path

| Step | Expected |
|---|---|
| Press ⌥⇧4 | No overlay. The panel opens with the permission notice. |
| Click Allow Screen Recording… | macOS's own prompt appears once; Exhibit A is now in Privacy & Security, Screen & System Audio Recording. |
| Choose Deny (or close the prompt), then press ⌥⇧4 | Panel shows "Screen Recording is off for Exhibit A" in red with Open Privacy & Security… and Check Again. |
| Click Open Privacy & Security… | System Settings opens on Screen & System Audio Recording. No second system prompt. |
| Turn Exhibit A on, return, click Check Again | If macOS asks to quit and reopen, do it. Afterwards the notice is gone, the pilot light is lit and "No captures yet" shows with ⌥⇧4 and ⌃⌥⇧4. |
| Settings, Permission | "Allowed" with a green light. |

## 3. Capture and edit (⌥⇧4)

| Step | Expected |
|---|---|
| Press ⌥⇧4 | Every display dims within about 100 ms; crosshair cursor; hint strip at the bottom of each display. The app you were in stays frontmost (its menu bar does not change). |
| Drag a region | Clear cutout with a white border and a point size label (for example `400 × 250`). |
| Release | Overlay closes. Since unit 5 the editor opens with the capture (`docs/product/unit5-live-checklist.md`); press Esc, then open the panel: the new capture is at the top with today's time and the point size. Select it: Open, Copy, Show in Finder, Delete. |
| Show in Finder | `<uuid>.exhibit` holding `original.png` and `document.json`. On a Retina display `original.png` is twice the point size in pixels and `document.json` has `"scale" : 2`. |
| Wait a few seconds, `cat document.json` | `targets` lists the text in the region (OCR ran in the background). |
| Press ⌥⇧4 then Esc | Overlay closes, nothing saved. |
| Press ⌥⇧4, Space, hover windows | The window under the pointer is clear and outlined; the rest dims. Hint changes to "Click a window". |
| Click a window | Capture of just that window's frame, no shadow; the row title is the app's name. Since issue 72 it is cut from the still at the hotkey, so a part covered by another window shows that window, and rounded corners show what was behind them. |
| Press ⌥⇧4, Space, Space | Back to region mode. |
| Press ⌥⇧4 then ↩ | The whole display under the pointer is captured, without the overlay or the cursor. Since issue 72 the menu bar glyph's panel is in it when it was open. |
| Two displays: start a drag on one and end on the other | The capture stops at the edge of the display where the drag started. |
| Mixed scales (Retina laptop plus a 1x monitor) | A capture from each has the right pixel size (2x and 1x) and is sharp. |
| On a P3 display, capture something saturated, then `sips -g profile original.png` and the same on an exported `-marked.png` | Write down the profile ScreenCaptureKit gives (issue 17). If it is Display P3, the export says Display P3 too and the colours match the screen; if it is sRGB, ScreenCaptureKit converted at capture and only imported P3 files keep P3. |
| Press ⌥⇧4 again while the overlay is up | Ignored; one overlay, no crash. |

## 3a. Nothing changes at the hotkey (issue 72)

| Step | Expected |
|---|---|
| Open the panel, press ⌥⇧4 | The panel stays open under the dim; nothing on screen moves or redraws. Drag over the panel: the capture shows it. |
| Panel open, press ⌥⇧4, click once on the overlay, then Esc | The panel is still open and still takes typing, as before the hotkey. |
| Panel open, press ⌥⇧4, drag a region | The panel closes once the capture is taken. |
| With an editor open, press ⌥⇧4, drag over the editor (or Space and click it) | The capture is the editor, not what is behind it. |
| In another app, open a menu or a popover (Safari's downloads, a menu bar extra), then press ⌥⇧4 and drag over it | The menu or popover is in the capture. Note whether it is still open on screen after the overlay closes, and whether the app you were in is still frontmost. |
| Hover a button that highlights, press ⌥⇧4 | The highlight is in the capture even if it fades under the overlay. |
| On each of three displays (2x main, 2x offset to the right, 1x above), drag a region | Each capture has that display's pixel size and is sharp; the dimmed still lines up exactly with the real screen, with no shift or blur. |
| Keychain Access on screen, press ⌥⇧4 | Its window is black with the label in the still the overlay shows, and in the capture. Space and click it: refused, the panel says why. |
| Time from the key to the dim | Write it down; `CaptureTests` print the freeze time as "stills of N displays". |

Recorded by `CaptureTests.testRecordsTheColourSpace` on 2026-11-18 (macOS 26.6.2, built-in Liquid Retina XDR): ScreenCaptureKit returns the display's own ICC profile (unnamed, wide gamut, 4064 bytes), not sRGB and not the named Display P3 space; the saved `original.png` and an export keep that profile, and the renderer draws in it. Sections 3 and 4, apart from the hotkey press itself and the editor taking focus (issue 53), are covered by `Scripts/run-e2e-capture.sh` on that Mac's three displays (2x, 2x and 1x).

## 4. Capture to clipboard (⌃⌥⇧4)

| Step | Expected |
|---|---|
| Press ⌃⌥⇧4, drag | No window or panel opens. |
| Paste into Preview (File, New from Clipboard) or a chat app | The PNG at full pixel size. |
| Open the panel | The capture is in history too. |

## 5. Hotkeys and takeover

| Step | Expected |
|---|---|
| Settings, Hotkeys, click the Capture and edit recorder, press ⌃⌥C | Accepted; Reset appears; ⌃⌥C now captures and ⌥⇧4 does nothing. |
| Record ⌃⌥⇧4 for Capture and edit | Refused: "Capture to clipboard already uses this shortcut." The recorder shows the previous key. |
| Record ⇧⌘4 while macOS's shortcut is on | Refused (by Exhibit A or by the recorder's own system check), naming the screenshot shortcut. |
| Click Reset | Back to ⌥⇧4. |
| Click Open Keyboard Settings… | System Settings opens on Keyboard. Note whether it lands on Keyboard (expected) or elsewhere. |
| Turn off both "selected area" shortcuts under Keyboard Shortcuts, Screenshots, then bring Exhibit A's Settings forward | "macOS screenshot shortcuts: Turned off". The hotkeys read ⇧⌘4 and ⌃⇧⌘4. |
| Press ⇧⌘4 without logging out | Exhibit A's overlay, not macOS's. If macOS still answers, note it: that means a logout is needed for the key to be free. |
| Turn the system shortcuts back on, open the panel | Exhibit A returns to ⌥⇧4 and ⌃⌥⇧4. |

## 6. History and retention

| Step | Expected |
|---|---|
| Make three captures, open the panel | Newest first, thumbnails, sizes in points. |
| Select a row, Copy | Image on the clipboard. |
| Select a row, Delete | Gone from the panel and from disk. No confirmation (single delete). |
| Settings, Keep captures: 1 day; set a capture's `createdAt` in `document.json` to two days ago; reopen the panel | That capture is swept. |
| Settings, Delete All… | A confirmation; after confirming, the folder holds only `.metadata_never_index`. |
| `mdfind -onlyin ~/Library/Application\ Support/Exhibit\ A/Captures document` | No results (Spotlight skips the folder). |
| Force quit Exhibit A mid-capture, relaunch | No `.partial` folders remain after the panel opens; history is intact. |

## 7. Idle and network

| Step | Expected |
|---|---|
| Leave Exhibit A idle for five minutes, Activity Monitor | 0% CPU, no wakeups from timers. |
| Little Snitch or `nettop -p <pid>` during all of the above | No network connections. |

## 8. Agent tag (needs unit 6)

The "by agent" tag and the glyph flash need the capture bridge (unit 6). The tag's look is in `docs/samples/app/panel-history-*.png`.
