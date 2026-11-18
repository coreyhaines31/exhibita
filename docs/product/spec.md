# Exhibit A — v1 spec

Draft, 2026-11-18. Verdict: **unproven**. Units 0 to 3 are built (core, targets, CLI on files, interpreter spike); the app is not.

A Mac menu bar screenshot tool where marking up takes single keystrokes, a spoken sentence, or one CLI command from an agent. Tenth app in the Brushed family. Local, free, no account. CLI binary: `exhibit`.

## Decisions

Decided 2026-11-18. Corey set the first and delegated the rest ("I trust your judgment").

1. **Spoken instructions are interpreted on the Mac.** A fixed grammar handles common commands with no model; free-form sentences go to a local model the user runs. Apple's on-device model was measured in unit 0 and is left out of v1: it got 29% of held-out instructions right and over-blurred heavily (see `docs/product/spike-interpreter.md`). Re-run the eval when Apple ships a new model.
2. **Originals are kept for 30 days** so marks stay editable, outside Time Machine, with a one-click purge. The retention period is a setting, and "discard on export" is one of its values.
3. **Licence: FSL-1.1-MIT** with a separately licensed `ee/` directory for paid code, as Midnight Oil does. Site and README say "free, source available", not "open source". The repo is private until release.
4. **No own-key cloud models in v1.** Free means on-device or a local model the user runs; hosted interpretation is a paid cloud feature.
5. **Name screening** (a web search and the first USPTO hits) is treated as enough for a free app. No filing planned.

## Free and paid

Same shape as Midnight Oil and Kill Cord: the app is free with its source available, and money comes from teams and cloud.

| | Free, source available, local | Paid, later |
|---|---|---|
| Capture, all seven marks, redaction, history | Yes | |
| CLI and MCP for agents | Yes | |
| Voice with the built-in grammar | Yes | |
| Free-form instructions | A local model the user runs (an Ollama or LM Studio endpoint) | Hosted interpretation, no setup |
| Cloud | | Share links, synced history across Macs |
| Teams | | Shared library, team-wide never-capture and auto-redact rules, shared mark styles, managed deployment |

Nothing paid is built in v1, and v1 has no account. What v1 does so the paid tier is not a retrofit:

- The interpreter sits behind one interface, so a hosted one is a new implementation, not a rewrite.
- Captures have stable IDs and a documented on-disk format, so they can sync or upload later.
- Never-capture and auto-redact rules live in one policy file, so a team or MDM profile can supply it later.
- An `ee/` directory is reserved for paid code under its own licence.
- When accounts arrive they use Better Auth with the organization plugin, so a person can belong to several teams from the start.

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

**Out:** video and GIF recording, scrolling capture, accounts and every paid cloud or Teams feature (share links, sync, hosted interpretation), backgrounds and device frames, accessibility-tree targeting (first thing after v1), Windows and iOS.

### Better-model test

The app contributes capture, the geometry of what is on screen, a deterministic renderer, permissions and speed. The model only chooses which listed targets an instruction refers to. A better model resolves vaguer instructions against the same list, so the app gets more useful. It becomes less useful if macOS ships spoken markup itself.

## How it fits together

Every capture is one document: the original image, a list of targets found in it, and a list of marks. Hand, voice and CLI are three ways of writing the same marks; one renderer flattens them for export.

- **Capture:** ScreenCaptureKit takes a region, window or display. The app owns the Screen Recording grant.
- **Targets:** Vision OCR returns every text run with its box. Detectors tag emails, keys, cards, phone numbers and faces (secret detection reuses On Hand's patterns). Window frames come with the capture.
- **Marks:** each mark is a small record (kind, target or rectangle, style), stored beside the original and never baked in until export.
- **Render:** export flattens marks into a new PNG. Redacted regions are filled before blurring so original pixels are not recoverable from the output.

## Keys

Two global hotkeys, matching the two things Corey does most. Both are remappable.

| Hotkey | After takeover | Before takeover (assumed) | What happens |
|---|---|---|---|
| Capture and edit | ⌘⇧4 | ⌥⇧4 | Select, then the editor opens in place |
| Capture to clipboard | ⌃⌘⇧4 | ⌃⌥⇧4 | Select, and the image is on the clipboard. No window opens |

Onboarding offers to take over the system shortcuts: macOS's own screenshot shortcuts have to be turned off in System Settings → Keyboard → Keyboard Shortcuts → Screenshots first, and the app links straight to that pane. Whether the app can flip those settings itself is to be verified in unit 4.

After either hotkey: drag for a region, Space to pick a window, ↩ for the whole screen. A clipboard capture still lands in history, so it can be opened and marked up afterwards.

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
| "Hide anything that identifies the customer" | Model picks names, emails, account IDs from the list | Model tier; needs a local model set up |
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
| Speech model downloading | Progress with size on first dictation; cancelable. Rare on macOS 26, where the system transcriber needed no download in the spike |
| Listening / interpreting | Live transcript while held, then a short working state; no success before marks exist |
| Partial match | "Blurred 4 emails. Couldn't find: pricing button." Found marks applied |
| Nothing understood | Transcript shown with "No changes made" |
| Needs a model | The grammar declined and no model is set up: transcript shown with "This needs a model. Set one up in Settings." Nothing changes |
| Model edit applied | Each mark is named in the summary ("Blurred 4 emails, circled Pricing"), because about 1 model answer in 10 is wrong; one ⌘Z removes the batch |
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
| Analytics | N/A | Zero telemetry. Network calls: Sparkle update check and a one-time speech model download. A local model endpoint, if the user sets one, stays on their machine |
| Agent access | Yes | CLI and MCP share the app's capture rules |

Controls:

- **Redaction is destructive on export.** Exported files are flattened pixels with no layers and no copy of the original. Test: two captures that differ only in the text under a blur produce identical output in that region.
- **Originals on disk are the main stored risk.** Plain files in Application Support, excluded from Time Machine, kept 30 days by default (a setting), deleted as files on purge.
- **Never-capture list.** Password managers and Keychain Access by default, editable. Applies to people and agents.
- **Agent captures are visible.** Flash, history tag, and auto-blur of detected secrets before the agent receives the image, on by default.
- **Screen text is untrusted.** `targets` output is labelled as on-screen content so agents treat it as data.
- **Models only see labels.** Any model, local or (later) hosted, receives the transcript and target labels with secrets as placeholders; never the image. The local endpoint setting accepts loopback addresses only in v1.

Residual risks: secret detection is pattern matching and will miss things; anything that can run the CLI as the user can already read the screen by other means.

## Build units

CLI on files comes first: useful to agents before any UI exists, needs no permissions, and becomes the test harness. Build order is 1, 2, 3, then 0 (the spike scores interpreters against real target lists, which need the CLI), then 4 onward.

| Unit | What | Accepted when |
|---|---|---|
| 0 Spike | Interpreter eval and speech latency check | Done: 62 instructions over 10 screenshots; results in `docs/product/spike-interpreter.md` |
| 1 Core | Document format, marks, renderer | Golden-image tests pass for all seven marks; redaction test passes |
| 2 Targets | OCR, secret and face detectors | Fixtures return expected text boxes and kinds |
| 3 CLI on files | Selectors and every markup command | `exhibit blur fixture.png --kind email` hides all fixture emails; unmatched selectors exit non-zero |
| 4 App shell | Status item, permission onboarding, hotkey, capture, history store | First-use journey works on a clean user account; denial path shown |
| 5 Editor | In-place editor, single-key tools, text snapping, undo, copy and save | The seven-keystroke example works; marks survive a force quit |
| 6 Capture bridge | CLI asks the app for live captures; never-capture list; agent tagging | `exhibit capture --window` returns an image without any window changing focus |
| 7 Voice | Push-to-talk, transcription, grammar interpreter, partial-result UI | Grammar rows in the voice table pass on fixtures |
| 8 Model tier | Local model endpoint as the free-form interpreter, plus `say`. Refs are validated in the app; no reliance on structured output | On a fresh held-out set of 30 or more: grammar then model at least 85% exact; zero missed redaction targets on kind or literal redactions; not-found right in at least 4 of 5; model step median at most 3 s and p90 at most 10 s |
| 9 MCP | stdio server over the CLI commands | Claude Code captures, blurs and exports through it |
| 10 Release | Sparkle, notarization, cask, launch at login, `--demo --snapshot`, icon | Notarized DMG opens on a second Mac; update from the previous build works |

**Family membership.** Exhibit A ships as a full member of the Mac app family, the same as its nine siblings: PanelKit for the panel and settings, the Brushed look (metal, black, chrome, colour only in lights), an icon and menu bar glyph from `mac-app-kit` that differ in concept from the others, a site built on site-kit at `exhibitaformac.com`, a cask in `coreyhaines31/homebrew-tap`, and a place in every sibling site's "More free Mac apps" section and footer.

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
| Originals handling and purge | not assessed, blocking | Unit 4 |
| Agent capture rules | not assessed | Unit 6 |
| Dictation accuracy | not assessed | Measured on synthetic speech only (8% word errors); real voices not assessed |
| Performance | not assessed | No baseline |
| Notarization and update path | not assessed, blocking | Never run for this app |
| Orgs, billing, backend, analytics | justified N/A | Local single-user utility, zero telemetry |

### Not verified yet

- How smaller local models (3B to 8B) do as the free-form interpreter; only one 27B model was measured, at 90% exact with the grammar first.
- Speech on macOS 14 and 15. macOS 26 uses the system `SpeechTranscriber` (fast in the spike, no prompt for files); WhisperKit for older systems is still an unverified assumption.
- How often macOS 15+ re-prompts for Screen Recording.
- Whether the app can turn off the system ⌘⇧4 shortcut itself, or can only link to the setting.
- Competitor facts (Shotcrisp, Lasso, Shotmark, Snapperon, CleanShot X) come from product pages read on 2026-11-18, not hands-on use.
- Name screening for "Exhibit A" covered a web search and the first USPTO hits only.
