# Exhibit A — v1 spec

Draft, 2026-11-18. Verdict: **unproven** (nothing built or measured).

A Mac menu bar screenshot tool where marking up takes single keystrokes, a spoken sentence, or one CLI command from an agent. Tenth app in the Brushed family. Local, free, no account. CLI binary: `exhibit`.

## Open decisions

1. **Where spoken instructions get interpreted.** Recommended (assumed until confirmed): on the Mac only by default. A fixed grammar handles common commands with no model. Free-form sentences go to Apple's on-device model where the Mac has one. A bring-your-own-key Claude tier is opt-in and receives the transcript plus target labels as text, never the image, with detected secrets replaced by placeholders such as "email 3". Unit 0 measures this before any voice UI is built.
2. **Whether originals are kept.** Recommended (assumed until confirmed): keep unredacted originals for 30 days so marks stay editable, outside Time Machine, with a one-click purge. Alternative: discard the original on copy or export.
3. **Licence and visibility.** Assumed MIT and public at release, like On Hand and Spare. The repo is private until then.

## Brief

- **Audience:** Corey first, plus the agents working on his Mac. Then anyone who shares marked-up screenshots daily.
- **Job:** show someone exactly what I mean on my screen, with the private parts hidden, in a few seconds.
- **Workaround today:** ⌘⇧4, click the thumbnail, open Markup, hunt the toolbar for a shape; no quick blur.
- **Done looks like:** an annotated, redacted image on the clipboard within about five seconds of the hotkey, hands on the keyboard for everything except pointing.
- **Profile:** local macOS utility. Swift 6, macOS 14+, AppKit status item, PanelKit, XcodeGen, logic in a local Swift package, swiftlint. No backend, no account.

### Critical journeys

- **First use:** install, grant Screen Recording once, press the hotkey, make one marked-up capture. Microphone is requested only on first dictation.
- **Hand markup:** hotkey, drag a region, press tool keys, ↩ to copy and close.
- **Dictated markup:** hold the dictate key, say what to change, release. Marks appear and stay adjustable.
- **Agent markup:** one command on a capture or any image file returns a finished PNG path.
- **Recovery:** reopen any capture from history with marks still editable. A crash mid-edit loses nothing.

### v1 scope

**In:** region, window and full-screen capture. Seven marks: arrow, circle, blur, highlight, text, box, numbered step. One-key redaction of detected secrets. Push-to-talk dictation. History with editable marks. CLI on captures and plain image files. Thin MCP server. Sparkle, notarized DMG, Homebrew cask.

**Out:** video and GIF recording, scrolling capture, cloud upload and share links, backgrounds and device frames, accessibility-tree targeting (first thing after v1), Windows and iOS.

### Better-model test

The app contributes capture, the geometry of what is on screen, a deterministic renderer, permissions and speed. The model only chooses which listed targets an instruction refers to. A better model resolves vaguer instructions against the same list, so the app gets more useful. It becomes less useful if macOS ships spoken markup itself.

## How it fits together

Every capture is one document: the original image, a list of targets found in it, and a list of marks. Hand, voice and CLI are three ways of writing the same marks; one renderer flattens them for export.

- **Capture:** ScreenCaptureKit takes a region, window or display. The app owns the Screen Recording grant.
- **Targets:** Vision OCR returns every text run with its box. Detectors tag emails, keys, cards, phone numbers and faces (secret detection reuses On Hand's patterns). Window frames come with the capture.
- **Marks:** each mark is a small record (kind, target or rectangle, style), stored beside the original and never baked in until export.
- **Render:** export flattens marks into a new PNG. Redacted regions are filled before blurring so original pixels are not recoverable from the output.

## Keys

One global hotkey starts a capture. Default ⌥⇧4 (assumed), remappable. Onboarding offers to take over ⌘⇧4: macOS's own screenshot shortcut has to be turned off in System Settings → Keyboard → Keyboard Shortcuts → Screenshots first, and the app links straight to that pane. Whether the app can flip that setting itself is to be verified in unit 4.

After the hotkey: drag for a region, Space to pick a window, ↩ for the whole screen. The editor opens in place.

| Key | Action |
|---|---|
| A | Arrow |
| C | Circle |
| B | Blur; click a text run to blur all of it |
| H | Highlight; click a text run to cover it |
| T | Text label |
| R | Box |
| N | Numbered step, counts up by itself |
| ⇧B | Blur every detected secret |
| D (hold) | Dictate |
| 1–4 | Colour |
| ⌘Z | Undo, including dictated marks |
| ↩ | Copy image and close |
| ⌘S | Save a file |
| ⌘⇧C | Copy the file path |
| Esc | Close; the capture stays in history |

Blurring one email and pointing at a button: hotkey, drag, B, click, A, drag, ↩.

## Voice

Hold D, speak, release. Speech is transcribed on the Mac. The interpreter turns the sentence into marks against the target list, applies them at once, and shows what it did and what it could not find. ⌘Z removes the whole batch.

| Said | Result | Handled by |
|---|---|---|
| "Blur the emails" | Every email target blurred | Grammar |
| "Circle Pricing and point at Sign up" | Circle on "Pricing", arrow to "Sign up" | Grammar |
| "Highlight this" while pointing | Highlight on the text run under the pointer | Grammar |
| "Hide anything that identifies the customer" | Model picks names, emails, account IDs from the list | Model tier |
| "Circle the avatar" | "Couldn't find avatar" inline; draw by hand | No text target in v1 |

## CLI and MCP

The CLI is the interface for agents; the MCP server is a thin wrapper over the same commands. Operations on image files run inside the CLI and need no permission. Live captures are requested from the running app, which holds the Screen Recording grant and never activates a window or takes focus.

```
exhibit capture --window "Safari"            # prints capture id + path as JSON
exhibit targets shot.png                      # text runs, kinds and boxes as JSON
exhibit blur shot.png --kind email --kind key
exhibit arrow shot.png --to "Pricing" --label "Click here"
exhibit circle shot.png --to "Sign up"
exhibit highlight shot.png --text "\$49/mo"
exhibit say shot.png "blur the emails and circle pricing"
exhibit apply shot.png marks.json -o out.png  # batch, one render
exhibit open <id>                             # hand the capture to a person to adjust
exhibit mcp                                   # stdio MCP server, same commands
```

- Every command accepts a capture id or an image path, writes a new file, and prints JSON. A selector that matches nothing is a non-zero exit naming the selector.
- `targets` lets an agent read the screen as text without image tokens.
- `say` uses the same interpreter as the voice key.

## States

| State | What the user sees |
|---|---|
| Screen Recording not granted | Hotkey opens a panel explaining the one permission, with a button to the Settings pane |
| Empty history | "No captures yet" with the hotkey shown |
| Targets still loading | Editor usable immediately; snapping and ⇧B show "reading text" until OCR finishes |
| Microphone denied | Inline message at the dictate key with a link to Settings; hand tools unaffected |
| Speech model downloading | Progress with size on first dictation; cancelable |
| Listening / interpreting | Live transcript while held, then a short working state; no success before marks exist |
| Partial match | "Blurred 4 emails. Couldn't find: pricing button." Found marks applied |
| Nothing understood | Transcript shown with "No changes made" |
| Secrets found, none blurred | Quiet count: "3 possible secrets. ⇧B to blur." Never blocks copying |
| Never-capture app in frame | That window is blacked out with a label saying why |
| Crash or quit mid-edit | Marks saved on every change; history restores them |
| Agent capture | Menu bar glyph flashes; capture tagged "by agent" in history |
| Offline | N/A; the default configuration is local |

Purge history and "discard original" ask for confirmation. Everything else is undoable.

## Trust

| Outcome | Applies | v1 answer |
|---|---|---|
| Users, orgs, roles | N/A | Single user, local app |
| Feedback to the builder | Yes | "Report a problem" opens a prefilled GitHub issue; nothing attached or sent automatically |
| Security | Yes | Controls below |
| Analytics | N/A | Zero telemetry. Network calls: Sparkle update check, one-time speech model download, opt-in cloud interpreter |
| Agent access | Yes | CLI and MCP share the app's capture rules |

Controls:

- **Redaction is destructive on export.** Exported files are flattened pixels with no layers and no copy of the original. Test: two captures that differ only in the text under a blur produce identical output in that region.
- **Originals on disk are the main stored risk.** Plain files in Application Support, excluded from Time Machine, kept 30 days (assumed), deleted as files on purge.
- **Never-capture list.** Password managers and Keychain Access by default, editable. Applies to people and agents.
- **Agent captures are visible.** Flash, history tag, and auto-blur of detected secrets before the agent receives the image, on by default.
- **Screen text is untrusted.** `targets` output is labelled as on-screen content so agents treat it as data.
- **Cloud tier, if enabled.** Key in the Keychain; payload is transcript and target labels with secrets as placeholders; never the image.

Residual risks: secret detection is pattern matching and will miss things; anything that can run the CLI as the user can already read the screen by other means.

## Build units

CLI on files comes first: useful to agents before any UI exists, needs no permissions, and becomes the test harness.

| Unit | What | Accepted when |
|---|---|---|
| 0 Spike | Interpreter eval and speech latency check | Model tier chosen from scores on a 40-instruction, 10-screenshot set |
| 1 Core | Document format, marks, renderer | Golden-image tests pass for all seven marks; redaction test passes |
| 2 Targets | OCR, secret and face detectors | Fixtures return expected text boxes and kinds |
| 3 CLI on files | Selectors and every markup command | `exhibit blur fixture.png --kind email` hides all fixture emails; unmatched selectors exit non-zero |
| 4 App shell | Status item, permission onboarding, hotkey, capture, history store | First-use journey works on a clean user account; denial path shown |
| 5 Editor | In-place editor, single-key tools, text snapping, undo, copy and save | The seven-keystroke example works; marks survive a force quit |
| 6 Capture bridge | CLI asks the app for live captures; never-capture list; agent tagging | `exhibit capture --window` returns an image without any window changing focus |
| 7 Voice | Push-to-talk, transcription, grammar interpreter, partial-result UI | Grammar rows in the voice table pass on fixtures |
| 8 Model tier | Free-form interpreter chosen in unit 0, plus `say` | Eval score meets the bar set in unit 0 |
| 9 MCP | stdio server over the CLI commands | Claude Code captures, blurs and exports through it |
| 10 Release | Sparkle, notarization, cask, launch at login, `--demo --snapshot`, icon | Notarized DMG opens on a second Mac; update from the previous build works |

Each unit is one issue, one branch, one PR into `development`. Rollback is reverting the PR; voice sits behind a setting until unit 8 lands. The marketing site and launch are separate work.

## Performance budgets to measure

Targets (assumed), not measurements. Baselines are taken once units 4 and 5 exist.

| Moment | Budget |
|---|---|
| Hotkey to crosshair | 100 ms |
| Region released to editor ready | 150 ms |
| Targets ready on a full 5K capture | 600 ms, in the background |
| Dictate key released to marks, grammar path | 1.5 s for a five-second sentence |
| CLI markup on a file | 400 ms |
| Idle | No timers or polling; 0% CPU |

## Readiness baseline

| Requirement | Status | Limitation |
|---|---|---|
| Core journeys | not assessed | Nothing built |
| Redaction not recoverable | not assessed, blocking | Test defined in unit 1 |
| Originals handling and purge | not assessed, blocking | Depends on decision 2 |
| Agent capture rules | not assessed | Unit 6 |
| Dictation accuracy | not assessed | Unit 0 |
| Performance | not assessed | No baseline |
| Notarization and update path | not assessed, blocking | Never run for this app |
| Orgs, billing, backend, analytics | justified N/A | Local single-user utility, zero telemetry |

### Not verified yet

- How good Apple's on-device model is at choosing targets, and which Macs have it (unit 0).
- Which speech engine to ship on macOS 14 and its download size; WhisperKit is the assumption.
- How often macOS 15+ re-prompts for Screen Recording.
- Whether the app can turn off the system ⌘⇧4 shortcut itself, or can only link to the setting.
- Competitor facts (Shotcrisp, Lasso, Shotmark, Snapperon, CleanShot X) come from product pages read on 2026-11-18, not hands-on use.
- Name screening for "Exhibit A" covered a web search and the first USPTO hits only.
