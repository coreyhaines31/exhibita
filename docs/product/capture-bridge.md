# Capture bridge

Unit 6. How `exhibit capture` and `exhibit open` reach the running app, which holds the Screen Recording grant, and what that channel does and does not protect. CLI reference: `docs/cli.md`, "Live captures". Code: `Packages/ExhibitCore/Sources/ExhibitBridge`, `App/Bridge`.

## Decision: a Unix domain socket under Application Support

`~/Library/Application Support/Exhibit A/Bridge/bridge.sock`, created by the app at launch.

| Option | Why or why not |
|---|---|
| **Unix domain socket** (chosen) | The CLI is a plain SwiftPM binary outside the app bundle, run by agents from any directory. A socket needs nothing from it but a path. The kernel tells each end the other's user id (`getpeereid`, which is `LOCAL_PEERCRED`), file modes limit who can connect, and it never touches the network. It is easy to test in process: server and client run against each other on a temporary path. |
| XPC Mach service | A Mach service the CLI can look up needs a launchd job (a LaunchAgent plist or `SMAppService` agent) and, to restrict callers, code signing requirements on both ends. The CLI is unsigned when built from source, and the app shell would grow a helper and a registration step. More moving parts for the same local reach. |
| `NSXPCConnection` to the app's own listener | An anonymous listener cannot be found by another process without a Mach service, which is the row above. |
| URL scheme (`exhibita://capture`) | Opening a URL goes through Launch Services: it can launch the app, it can activate it, and there is no reply channel, so the CLI could not get the capture id back without a second mechanism. It also cannot tell who asked. All three break unit 6's rules. |
| Loopback TCP | Any local user, and any process that can make a socket, could connect; there is no peer user id. Ruled out: no TCP anywhere. |
| Distributed notifications, Apple events | No reliable reply, no caller identity, and Apple events prompt for Automation permission. |

## Protocol

- One connection per request. The client writes one line of JSON, the server answers with one line and closes. Lines are at most 1 MiB; responses carry paths and counts, never pixels.
- Every message has `v` (protocol version, now 1) and `id` (the request id, echoed in the response). A server refuses another version with `unsupported_version`; a client refuses a response with another id.
- Requests: `{"v":1,"id":"...","method":"capture","capture":{"window":"Safari"}}`, `"method":"open","open":{"captureID":"<uuid>"}`, and `"method":"ping"`. Capture parameters are `window`, `display` (from 1) and `region` (`{x, y, width, height}` in points of that display, top-left origin).
- Responses carry exactly one of `capture`, `open`, `pong` or `error`. Errors are `{"code", "message", "candidates"?}`; codes are strings so a newer app's codes still reach an older CLI. The CLI maps them to its exit statuses (`docs/cli.md`).
- Timeouts: the server drops a client that has not sent its request line within 5 seconds and gives up writing after 10; the client waits 30 seconds by default (`--timeout`).

## Who can reach it

- The socket's directory is created 0700 (and tightened to 0700 if it exists), must be a real directory owned by this user, and the socket itself is 0600.
- The server checks the peer's user id on every connection and closes, without a word, any peer that is not this user. The client checks the server's user id too, so another account cannot stand in for the app.
- Starting the server never deletes a file that is not a socket, and never replaces a socket that another process still answers on (a second copy of the app fails to start its bridge and logs it). A stale socket left by a crash is replaced.
- The app never starts on a request: when nothing serves the socket, the CLI exits 7 `app_not_running`.
- `EXHIBIT_SUPPORT_DIR` moves the whole Application Support directory for the CLI (history, policy, socket). It exists for tests. The app ignores it.

## What a capture does

1. Screen Recording is checked with `CGPreflightScreenCaptureAccess`, which never prompts. Without it: `permission_not_granted`. Nothing asks.
2. `--window`: ScreenCaptureKit's on-screen windows in the window server's front-to-back order go through `WindowQuery`. A window of a never-capture app is refused (`never_capture`); titles of never-capture windows are left out of `ambiguous_window` lists. A display or region: listed apps are excluded through `SCContentFilter`, and their windows' whole frames are drawn black with "Hidden by Exhibit A: <app> is on the never-capture list" (`Blackout`). Covering too much is safe: a listed window partly behind another is still blacked out in full.
3. `SCScreenshotManager` takes the still image. No overlay, nothing activated, focus untouched.
4. The capture is saved to history with `capturedBy: agent`, so history shows "by agent", and the menu bar glyph blinks twice.
5. `TargetFinder` reads it. If that fails, the agent gets `capture_failed` and no image, because secrets could not be blurred; the person still has the capture.
6. Auto-blur (on by default, Settings): every email, key, card and phone target becomes a blur mark on the document, and `<id>.png` beside the bundle is rendered through the real renderer. Because the blurs are marks, every later CLI render of the capture id keeps them, and the person can remove them in the editor. `original.png` is never changed.
7. The response names the id, the bundle, the image, the size, the blur counts by kind and the blacked-out reasons.

`exhibit open <id>` opens the capture in the editor (`EditorWindows.open`), the one bridge request that brings a window forward, because handing the capture to a person is its purpose. The call site is the `present` closure in `AppDelegate.startBridge`.

## Never-capture list

One file, `~/Library/Application Support/Exhibit A/policy.json` (`docs/format.md`), so a team or a managed profile can supply it later. Defaults: 1Password (`com.1password.1password`), 1Password 7 (`com.agilebits.onepassword7`), Bitwarden (`com.bitwarden.desktop`), Dashlane and LastPass (by name: their bundle identifiers are not verified), KeePassXC (`org.keepassxc.keepassxc`), Passwords (`com.apple.Passwords` and its menu bar extra) and Keychain Access (`com.apple.keychainaccess`). An entry matches by bundle identifier or by app name, ignoring case. A damaged file, or one from a newer version, is ignored in favour of the defaults, so a broken file never switches protection off.

It applies to people too: a region or screen capture blacks listed windows out, and picking a listed window with Space is refused with a beep.

## Residual risks

- **Anything running as this user can use the bridge.** The uid check stops other accounts, not other programs of the same user. Such a program could already read the screen by other means if it has Screen Recording itself, and it can read history on disk without any permission. The bridge lends the app's Screen Recording grant to every process of this user; that is the feature, and the flash and "by agent" tag are how the person notices.
- **The original is on disk.** `bundle` points at the unblurred original, readable by the same user. Auto-blur keeps secrets out of what an agent is asked to read, not out of reach of a hostile one.
- **Detection is pattern matching** and misses things: names, addresses, secrets in images or odd formats. A capture's text may also be misread by OCR.
- **The never-capture list matches apps, not content.** A password shown in a browser tab or a terminal is captured. Names are matched as reported by macOS; an app that renames itself and changes its bundle identifier escapes the list until it is added again.
- **Blackout geometry is unverified on a live Mac** (window and display frames assumed to share ScreenCaptureKit's global top-left space). See `unit6-live-checklist.md`.
- **Window titles and app names come from the screen** and are returned to agents: a page title can say anything. They are labelled as data, not instructions.
- **Short race with the editor:** the bridge writes targets and blur marks to a new agent capture's `document.json` directly, before the history refresh that would let a person open it. A person who opens that capture from history within that moment could see the document without its blurs until the editor saves again.
- **A person's refused window pick** only beeps. A message in the panel is not built yet.
