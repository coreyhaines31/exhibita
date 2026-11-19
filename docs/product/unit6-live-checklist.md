# Unit 6 live checklist

Everything in unit 6 that only a person at a Mac can check. Package tests (the socket server and client against each other in process, with a fake capture provider), lint, the Debug build, the app's view tests and the offscreen Settings render passed; nothing below has been run. Unit 6 is accepted when `exhibit capture --window` returns an image without any window changing focus.

Build the app as in `unit4-live-checklist.md` and the CLI with `swift build -c release` in `Packages/ExhibitCore` (`.build/release/exhibit`). Screen Recording must be on for Exhibit A. Mark each line pass or fail with the macOS version.

## 1. Bridge and permission

| Step | Expected |
|---|---|
| Quit Exhibit A, run `exhibit capture` | Exit 7, `app_not_running`, telling you to open Exhibit A. The app does not start. |
| Open Exhibit A, `ls -la ~/Library/Application\ Support/Exhibit\ A/Bridge` | The directory is `drwx------`; `bridge.sock` is `srw-------`, owned by you. |
| From another user account, run `exhibit capture` with `EXHIBIT_SUPPORT_DIR` pointing at your Application Support folder | Fails (permission denied on the directory); nothing is captured. |
| Turn Screen Recording off for Exhibit A, run `exhibit capture` | Exit 8, `permission_not_granted`. No system prompt appears. Turn it back on. |
| Quit Exhibit A from the panel, list the Bridge folder | `bridge.sock` is gone. Force quit instead and reopen: the bridge starts again (the stale socket is replaced). |

## 2. Focus does not change (the acceptance test)

| Step | Expected |
|---|---|
| Put Safari frontmost with a text field focused and the caret blinking. From Terminal behind it (or over ssh), run `exhibit capture --window Safari` | JSON with `id`, `bundle`, `image`. Safari stays frontmost, its field keeps focus and the caret; Terminal does not come forward; no Exhibit A window or overlay appears. |
| Open `image` | Safari's window alone, without its shadow, at Retina size. |
| `exhibit capture`, then `exhibit capture --display 2 --region 0,0,400,300` (with a second display) | The whole main display; a 400 by 300 point area at the top-left of display 2. Focus unchanged each time. Check that display 1 is the one with the menu bar. |
| `exhibit capture --window Notes` with two Notes windows open | The frontmost Notes window. A title fragment matching two windows exits 4 `ambiguous_window` with `windows`; `--window Nothing` exits 3 `window_not_found`. |

## 3. Agent captures are visible

| Step | Expected |
|---|---|
| Watch the menu bar while running `exhibit capture` | The Exhibit A glyph blinks twice. Nothing else changes. |
| Open the panel | The new capture is first in history with the "by agent" tag. |
| `exhibit open <id>` | The editor opens on that capture, with the auto-blurs as marks you can select and delete. |

## 4. Auto-blur on a real window

| Step | Expected |
|---|---|
| Show a page with an `example.com` email, a made-up API key and a test card number; `exhibit capture --window Safari` | `autoBlur.blurred` counts them, and in `image` each is blurred and unreadable. |
| Open the bundle's `original.png` | Unblurred: the original is untouched. |
| `exhibit circle <id> --text "<a word on the page>"` | The output keeps the blurs. |
| Settings, Privacy: turn "Blur secrets before agents see them" off and capture again | `autoBlur.enabled` is false, `blurred` is 0 and the image is unblurred. Turn it back on. |

## 5. Never-capture list

| Step | Expected |
|---|---|
| Open Keychain Access; `exhibit capture --window "Keychain Access"` | Exit 9, `never_capture`, naming Keychain Access. Nothing new in history. |
| With Keychain Access on screen, `exhibit capture` | Its whole window area is black with "Hidden by Exhibit A: Keychain Access is on the never-capture list"; `blackedOut` names it; nothing behind it shows. Check that the box sits exactly over the window on a Retina and a 1x display, and on a display left of or above the main one. |
| Hotkey, drag a region over Keychain Access | The same black, labelled box in the saved capture. |
| Hotkey, Space, click Keychain Access's window | A beep; nothing is saved. |
| With 1Password, Bitwarden, KeePassXC or Passwords installed, repeat the window check | Refused. Note each app's real bundle identifier; Dashlane and LastPass are matched by name only. |
| Settings, Privacy: Remove Keychain Access and capture its window | Captured. Restore Defaults puts it back; `policy.json` follows every change. |
| Add App, Choose App…, pick an app, capture its window | Refused. |
| Write `{` into `policy.json` and reopen Settings | The defaults apply and a warning names the file. |

## 6. MCP from Claude Code

| Step | Expected |
|---|---|
| `claude mcp add exhibit -- /path/to/exhibit mcp`; ask Claude Code to capture Safari, blur the emails and export | It calls `capture`, then `mark` or `apply` with the returned `id`, and names the output PNG. Focus stays where it was; the glyph blinks. |
| Quit Exhibit A and ask again | The tool returns `app_not_running`, and Claude Code says to open Exhibit A. |
| Ask it to open the capture for you | `open` brings up the editor on it. |
