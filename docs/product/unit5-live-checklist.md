# Unit 5 live checklist

Everything in unit 5 (the editor) that only a person at a Mac can check. The `ExhibitEditor` unit tests, lint, the Debug build, the app tests and the offscreen renders in `docs/samples/app/editor-*.png` passed; nothing below has been run. Unit 5 is accepted when the seven-keystroke example works and marks survive a force quit.

Build as in `docs/product/unit4-live-checklist.md` (a signed build keeps the Screen Recording grant between rebuilds). Screen Recording must already be allowed. Hotkeys below are the defaults before takeover (⌥⇧4 and ⌃⌥⇧4); use ⇧⌘4 and ⌃⇧⌘4 if the system shortcuts are off.

For snapping, open a page with an email address, an API key or similar made-up secret, and a button, for example a settings page on a test account. Use `example.com` addresses.

Mark each line pass or fail with the macOS version and the display (built-in Retina, external 1x).

## 1. The seven keystrokes (acceptance)

| Step | Expected |
|---|---|
| Start a stopwatch, press ⌥⇧4 | Overlay as in unit 4. |
| Drag a region holding an email and a button | The editor window opens centred on the same display, comes to the front and takes keys at once (no click needed first). The capture shows at its own size (sharp, 1:1 on that display) when it fits. Status strip: "Reading text" with an amber light, then within about a second "N possible secrets. ⇧B to blur." |
| Press B, click the email | The email is covered by the frosted blur within a frame; the blur covers exactly the address, not the whole line. |
| Press A, drag from empty space to the button | Arrow from where you pressed; its head stops just outside the button on the side facing the tail. |
| Press ↩ | The window closes. Stop the stopwatch. |
| Paste into another app (Messages, Slack, a Notes note, Preview's New from Clipboard) | The image is the marked capture: email blurred, arrow drawn, nothing else. The blurred area shows no readable characters even zoomed in. |
| Note the stopwatch time | Target: about five seconds from hotkey to clipboard. Write down the time. |

## 2. Each tool

| Step | Expected |
|---|---|
| Toolbar | Keys A C B H T R N V with names under them, the current tool as a reversed plate; four colour lights 1 to 4 with the current one lit; undo and redo keys; the status strip with ↩ Copy, ⌘S Save, ⇧⌘C Path, Esc Close. Light and dark appearance both match `docs/samples/app/editor-*`. |
| A, drag | Arrow from press to release, red. A, click on a word: an arrow is placed pointing at that line with its tail on empty space. |
| C, click a word | A circle around that line. C, drag: a circle around the dragged box. |
| B, click a plain line of text | The whole line is blurred. B, drag: the dragged box is blurred. While dragging, a grey stand-in shows; on release it becomes the real blur. |
| H, click a line | Yellow marker over the whole line; text stays readable. |
| T, click, type "Look here", ↩ | A red label appears where you clicked and fills as you type (letters do not switch tools while typing). ↩ ends typing and does not close the window. T, click, Esc with nothing typed: no label is left. |
| R, click a button | A box around it. R, drag: a box. |
| N, click three places | Discs 1, 2, 3. ⌘Z, then N click: the new disc is 3 again. |
| 1 to 4 | The lit colour changes; the next mark uses it; the selected mark (the one just drawn) recolours. Highlight stays yellow until a colour is chosen. |
| D | Nothing happens (dictation is unit 7). |

## 3. Select, move, resize, delete

| Step | Expected |
|---|---|
| V, click a mark | Dashed outline (handles only for an arrow). |
| Drag it | An outline follows the pointer; on release the mark moves. A plain click does not move it. |
| Drag a corner handle of a box, or an end of an arrow | It resizes from that corner or end. |
| ⌫ | The selected mark is removed. ⌘Z brings it back. |

## 4. Snapping and secrets on a real page

| Step | Expected |
|---|---|
| Capture a page with two emails and a key | Status: "3 possible secrets. ⇧B to blur." |
| ⇧B straight after the editor opens, before text is read | Status says "Reading text"; nothing changes. |
| ⇧B once the count shows | All three are blurred; status "Blurred 3 possible secrets"; after the next key the count is gone. ⌘Z once removes all three. |
| Blur one email by hand, then ⇧B | Only the other two are added. |
| B, click empty background | "No text here. Drag to draw." Nothing added. |
| Click a line with a small font, a line in a dark theme, a word in a table | The mark covers that line. Note any line that does not snap. |

## 5. Undo and redo

| Step | Expected |
|---|---|
| Make five marks, ⌘Z five times | Removed newest first; the undo key dims at the end. |
| ⇧⌘Z | Redone in order. A new mark after an undo clears redo (redo key dims). |

## 6. Marks survive a force quit

| Step | Expected |
|---|---|
| Open the editor, add three marks, wait one second | |
| `killall -9 "Exhibit A"` in Terminal | The app is gone. |
| Reopen Exhibit A, open the panel | The capture is at the top of history. |
| Open (or double-click the row) | The editor opens with all three marks, and blurs are already blurred in the first frame (no flash of the original). |
| Add a mark and press Esc | The window closes; reopening shows the mark. Esc never deletes the capture. |

## 7. Export

| Step | Expected |
|---|---|
| ⌘S | A save sheet with a name like `Safari 2026-11-18 at 15.41.07-marked.png`. Save. Status "Saved". The file opens in Preview and matches the canvas. |
| `mdls -name kMDItemAcquisitionMake <file>`, `exiftool <file>` if installed | No camera, author or app metadata; only size and colour information. |
| ⇧⌘C | Status "Path copied". Paste in Terminal: a path under the temporary folder ending `-marked.png`; `open` it to check. |
| Settings, keep captures "Until exported"; capture, mark, ↩ | The image is on the clipboard and the capture is no longer in history. With 30 days, it stays. |

## 8. Displays

| Step | Expected |
|---|---|
| Retina display: capture a small region | Shown at its own size and sharp. Exported PNG is twice the point size in pixels; marks look the same thickness as on a 1x capture of the same region. |
| External 1x display: capture there | The editor opens centred on that display, not the main one. |
| Capture a whole 5K or 4K display (↩ in the overlay) | The editor scales the capture down to fit the screen; the mark under the pointer is where you click; clicking a word still snaps. Note how long the editor takes to appear and how long a blur takes to show after release (budget: editor ready in 150 ms). |
| Space for a window, click a window on the second display | The editor opens on that display. |

## 9. Focus and the rest of the app

| Step | Expected |
|---|---|
| Open the editor while another app is frontmost | The editor is key: the first key press picks a tool, no click needed. |
| Open the panel's history, select a row, Open | The panel closes and the editor opens with that capture's marks. Opening the same capture twice brings the existing window forward. |
| With the editor open, press ⌃⌥⇧4 and capture | Capture to clipboard still works and opens no window. |
| Quit from the panel with an editor open | On relaunch, the last marks are there. |
