# Exhibit A

A free, source-available (FSL-1.1-MIT) macOS menu bar screenshot tool: mark up a capture with single keys, a spoken sentence, or one CLI command from an agent. Every capture is one document (original image, targets found in it, marks); hand, voice and CLI write the same marks, and one deterministic renderer flattens them. The product spec is `docs/product/spec.md`; the on-disk format is `docs/format.md`.

## Build and test

This machine's active developer directory is Command Line Tools, so prefix Swift commands:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd Packages/ExhibitCore && swift build && swift test
EXHIBIT_RECORD_GOLDENS=1 swift test   # rewrite goldens and docs/samples/*.png; look at every changed image
swiftlint --strict                     # from the repo root
swift build -c release                 # .build/release/exhibit, the CLI
```

App (XcodeGen; `ExhibitA.xcodeproj` is generated, never committed):

```sh
xcodegen generate
xcodebuild -project ExhibitA.xcodeproj -scheme ExhibitA -configuration Debug -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO build                     # the app, "Exhibit A.app"
xcodebuild -project ExhibitA.xcodeproj -scheme ExhibitA -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO test                      # ExhibitAViewTests: view models and offscreen renders
Scripts/render-app-samples.sh                       # rewrite docs/samples/app/*.png; look at every changed image
```

`xcodebuild` may rewrite `Packages/ExhibitCore/Package.resolved` with the app's packages; restore it before committing. What only a live Mac can check is in `docs/product/unit4-live-checklist.md` and `docs/product/unit5-live-checklist.md`.

`swift test` builds the `exhibit` binary too; `ExhibitCLITests/EndToEndTests` run it as a subprocess. `EXHIBIT_RECORD_GOLDENS=1` also regenerates `docs/samples/cli-demo.png` with the real binary.

Judge build, test and lint by exit code, never by grepping output.

## Architecture

- `Packages/ExhibitCore` (SwiftPM library, macOS 14, Swift 6; CoreGraphics, CoreText and ImageIO only, no AppKit, because the CLI links it):
  - `Geometry.swift`: `PixelPoint`, `PixelSize`, `PixelRect`. Pixels of the original, origin top-left.
  - `CaptureDocument.swift`, `Target.swift`, `Mark.swift`: the model. `TargetKind` keeps unknown kinds; `MarkKind` rejects them on purpose.
  - `CaptureBundle.swift`: `<uuid>.exhibit/` with `original.png` and `document.json`, atomic writes, `formatVersion` check.
  - `PNG.swift`: encode (metadata chunks stripped) and decode; `ExhibitError`.
  - `Renderer.swift`: `Renderer.render(original:marks:scale:)`; `MarkPainter.swift` and `LabelledMarks.swift` draw the marks.
  - `Redaction.swift`: blur fills built only from pixels outside every blur region.
- `Packages/ExhibitCore/Sources/ExhibitTargets` (library, adds Vision; ExhibitCore stays free of it): `TargetFinder().findTargets(in:)` returns `[Target]` in original pixels, top-left origin, ordered top to bottom then left to right.
  - OCR: `VNRecognizeTextRequest`, accurate, language correction off. One `.text` target per line, with per-word `spans`; `Target.rect(for:)` in ExhibitCore resolves a substring from spans, so selectors never re-run OCR.
  - `VisionGeometry.swift`: Vision's normalized bottom-left boxes to pixels, and `InkGrid`, which shrinks padded OCR boxes to the ink inside them.
  - `SensitivePatterns.swift`: email, key, card and phone patterns (keys and cards ported from On Hand). Sensitive targets carry no `text`, and their characters are masked in the line's text. Never name a file with "secret" or "credential" in it; agent read rules block those names.
  - Look-alikes: `Confusables` (ExhibitCore) folds Cyrillic, Greek, `Ø`, fullwidth and similar look-alikes to Latin, one UTF-16 unit to one. Detection and CLI selectors fold whole lines; stored text folds only mixed-script words (`docs/format.md`). Language settings do not stop Vision mixing scripts.
  - Faces: `VNDetectFaceRectanglesRequest`.
  - Vision runs one image at a time on a private serial queue, never on the caller's thread; there is an `async` form. Blocking Vision calls from Swift concurrency's cooperative pool deadlocked (`ConcurrentFindingTests`). OCR-heavy suites carry `.timeLimit`; run tests to a log file and stop a run that passes about 3 minutes.
- `Packages/ExhibitCore/Sources/ExhibitCLI` (library) and `Sources/exhibit` (the executable, product `exhibit`, a thin shell): the CLI on image files and bundles. Reference: `docs/cli.md`.
  - `Commands.swift`: swift-argument-parser commands (pinned exactly); `CLI.run(arguments:)` returns status, stdout and stderr without printing, so tests drive it in process.
  - `Selectors.swift`: `--text`/`--to`, `--regex`, `--kind`, `--rect` to candidates, using spans (no second OCR pass).
  - `Say.swift`, `SaySummary.swift`: `exhibit say`. The grammar first; `ModelInterpreter` only when it declines and a model is configured (`--model`/`EXHIBIT_MODEL` and friends); `needs_model` (exit 5) otherwise; `model_failed` (exit 6). Operations become `MarkSpec`s with `Selector.target(id)` and go through the same planner as `apply`. `CLI.run(arguments:environment:transport:)` injects the environment and a fake model transport in tests.
  - `Planner.swift`: no-match, ambiguous, `--all`/`--nth`, one `MarkSpec` per command or `marks.json` entry. `Placement` and `Clutter` (in ExhibitCore, shared with the editor): arrow tails, text labels and step discs, scored against word boxes. `ApplyFile.swift`: `marks.json`. `Session.swift`: input, targets (reused from a bundle's document), output naming, writing.
  - `MCPServer.swift`, `MCPTools.swift`, `MCPSchemas.swift`: `exhibit mcp`, a stdio MCP server (JSON-RPC, one message per line, `2025-06-18` with older versions negotiated). Tools `targets`, `mark`, `apply`, `say` build CLI argument lists and go through `CLI.run` (`apply` calls `ApplyFile` and `MarkRun` with inline marks), so results and errors are the CLI's JSON; failures are `isError` results. `say` reads model settings from the server's environment only. `MCPServer.handle(line:)` drives it in tests.
  - Exit codes and error `code` strings are a public contract (`docs/cli.md`); change them only on purpose.
  - `MarkLayout` in ExhibitCore exposes the renderer's label, caption and disc sizes for placement.
- `Packages/ExhibitCore/Sources/ExhibitInterpret` (library, ExhibitCore only): spoken or typed instructions to operations. Text in, never the image.
  - `Contract.swift`: `InterpretRequest` (instruction, targets with secrets masked, optional pointer) to `InterpretOutcome` (`.understood(Interpretation)` with operations and `notFound`, or `.declined`). `TargetPick` is `.id`, `.part` (a UTF-16 range of one target's text), `.kind` or `.text`, with the CLI selectors' meaning. `ChainedInterpreter` tries interpreters in order: grammar first, a model for what it declines.
  - `TargetListing.swift`: the list a model reads (`t1`, `t2`, ... refs, text and top-left corner in tens of pixels; sensitive targets as "hidden"; fully masked duplicate lines dropped) and the target under the pointer. Models answer with refs only, never coordinates.
  - `Resolution.swift`: picks to targets, and `applyEntry(in:)` to a `marks.json` entry, so interpretations go through `apply`.
  - `GrammarInterpreter` (`Grammar*.swift`, `Words.swift`): verbs, kinds, pointer words, whole-line and close (mis-heard) text matches. Declines anything needing judgement, any unknown phrase, any tie and any qualified kind ("her email", "the payments key"); reports a kind with no targets as not found. Blur and highlight take every line holding the phrase (blur also substrings, wrapped lines and every close mis-hearing): an ambiguous redaction declines or over-covers, never under-covers (`GrammarRedactionTests`). Marks other than blur go on the phrase alone (`.part`) when it is only part of a line (`GrammarNarrowingTests`); blur keeps whole lines.
  - `ModelPrompt.swift`, `ModelEndpoint.swift`, `ModelInterpreter.swift`: the local model tier. Ollama (`/api/chat`) or OpenAI-compatible (`/v1/chat/completions`) on loopback only (`ModelEndpoint.isLoopback`; the transport checks again and refuses redirects). No structured output; refs not in the listing are dropped. `ModelTransport` is blocking so the CLI stays synchronous; tests inject a fake one. This is the only network code, and it never leaves the Mac.
- `Packages/ExhibitCore/Sources/ExhibitEval` (executable `exhibit-eval`, not shipped): the interpreter eval. `swift run exhibit-eval interpret [--file instructions.json] [--split dev|heldout|all|<split>] [--only grammar,model,model-alone,apple] [--model qwen3.8:27b]` scores the shipping grammar and the shipping chain (grammar, then `ModelInterpreter` only where it declined) on `eval/interpreter`; `swift run exhibit-eval speech` times on-device transcription of `say` audio. Apple's model (FoundationModels) and SpeechAnalyzer sit behind macOS 26 checks and are not shipped. Findings: `docs/product/spike-interpreter.md`, `docs/product/heldout2-results.md`, `docs/product/model-latency.md` (where the model step's time goes; result rows carry `modelTimings`). Tune on `instructions.json` only. `instructions-heldout2.json`, `HELDOUT2.md` and the `calendar`, `crm` and `ticket` fixtures are held out: do not read them while changing the interpreter, and do not tune on them.
- `Packages/ExhibitCore/Sources/ExhibitStore` (library, ExhibitCore only, no AppKit): history. `CaptureStore` keeps captures as bundles in `~/Library/Application Support/Exhibit A/Captures` (injectable directory; excluded from Time Machine, `.metadata_never_index` for Spotlight), lists them newest first from `document.json` alone (`HistoryItem`; newer format versions and half-written bundles are skipped), saves documents atomically, deletes, purges, sweeps by `RetentionPolicy` (30 days by default; "until exported" deletes on export and sweeps the rest after 30 days) and makes ImageIO thumbnails.
- `Packages/ExhibitCore/Sources/ExhibitEditor` (library, no AppKit; ExhibitCore, ExhibitStore, ExhibitShell): the editor's brain, all unit tested. The app forwards pointer events in image pixels and keys, and draws what it says.
  - `EditorTool`, `EditorKeys`: the tools (A C B H T R N, V to select) and the spec's Keys table as `EditorKeymap`; D is unbound until unit 7.
  - `CaptureEditor` (`@Observable`, main actor) and `CaptureEditor+Pointer`: tool, colour (nil means each kind's default), selection, gestures to marks (a click snaps through `Snapping`; a drag draws; an arrow's head snaps with `Placement`), text labels typed in place, ⇧B, status (`EditorStatus`: notice, "Reading text", secrets count). Every mark change goes through `transact`, one undo step each (snapshots of the marks; ⇧B and a later dictated batch are one step). Drafts are outlines only; committed marks are drawn by `Renderer`.
  - `MarkHitTesting`: topmost mark at a point (blurs last), visible boxes, handles, move and resize.
  - `DocumentOwner`, `DocumentWriter`, `OpenCaptures`: one owner per open capture holds the in-memory document; every change is written whole, debounced 100 ms, on one serial queue, flushed on close. Background target results go through `OpenCaptures`: merged into an open document, held while one is loading, or written to the store on the same queue ahead of any later open. Nothing else writes an open capture's `document.json` (issue 8's race).
  - `EditorExport`: `Renderer` then `PNG.encode` only, and `-marked.png` file names.
- `Packages/ExhibitCore/Sources/ExhibitShell` (library, no AppKit): the app shell's decisions as tested logic. `KeyCombo`/`KeyModifiers` (bits equal `NSEvent.ModifierFlags`), `HotkeyAction` and `HotkeyBindings` (defaults ⌥⇧4 and ⌃⌥⇧4 until macOS's selection shortcuts are off, then ⇧⌘4 and ⌃⇧⌘4; custom keys stored, defaults not; refuses keys without ⌘/⌥/⌃, the other hotkey's key and keys an enabled system shortcut holds), `SystemScreenshotShortcuts` (parses `AppleSymbolicHotKeys` ids 28 to 31 and 184), `SelectionGeometry` (a drag in global Cocoa points to a display-local, top-left `sourceRect` grown outward to whole pixels; selections stay on the display where they started), `WindowPicker`, `HistoryPresentation` (rows, empty state, summary), `ScreenRecordingState`/`PanelContent`, and `CapturePolicy` (the never-capture hook, allows everything until unit 6).
- `App/` (the app target, a thin shell; bundle id `com.exhibitaformac.ExhibitA`, LSUIElement, PanelKit 0.2.1, KeyboardShortcuts 2.4.0 as in Midnight Oil and On Hand; no network code):
  - `Shell/`: `AppDelegate` wires everything; `AppModel` (`@Observable`: history, thumbnails, permission, bindings, retention; file work off the main thread); `StatusItemController` (glyph and popover); `Glyph` (placeholder template drawing; mac-app-kit's glyph replaces `Glyph.image`); `Preferences`; `LaunchAtLogin` (`SMAppService`, registered once by default in release builds only).
  - `Hotkeys/`: `HotkeyCenter` writes the keys in effect into KeyboardShortcuts (Carbon `RegisterEventHotKey`, no Accessibility) whenever bindings change.
  - `Capture/`: `SystemLinks` (`CGPreflightScreenCaptureAccess` only; `CGRequestScreenCaptureAccess` only from a button; reading the symbolic hot keys; System Settings links), `SelectionOverlay` (a non-activating panel per display: drag, Space for a window, ↩ for the display, Esc), `ScreenCapturer` (`SCScreenshotManager`, Exhibit A's own windows excluded), `CaptureController` (overlay to capture to history, clipboard PNG for capture to clipboard, `TargetFinder` in the background, its result routed through `OpenCaptures`). Capture and edit opens the editor centred on the display the capture came from.
  - `Panel/`, `Settings/`: SwiftUI over `AppModel` with action structs, so renders pass fixture models and no-op actions.
  - Hotkey takeover is read and link only: `docs/product/hotkey-takeover.md`.
  - `Editor/`: `EditorWindows` opens one `EditorWindowController` per capture (after capture and edit, and from history's Open or a double-click) and does what only the app can: clipboard, NSSavePanel, the ⇧⌘C file in the temporary folder, `didExport` on close. The editor window is the one place the app activates. `EditorWindow` sends keys to `CaptureEditor` before AppKit. `EditorView`, `EditorToolbar` (metal, key plates, colour lights, status strip) and `EditorCanvas` (the `EditorCanvasModel` render, which is `Renderer`'s output rendered before the window shows and again off the main thread on each change, plus outlines, handles and a caret) are SwiftUI. The capture shows at its own points where it fits and scaled to fit otherwise (`EditorLayout`).
- `ExhibitAViewTests/` (unhosted XCTest bundle that compiles the views itself): model checks plus renders of the panel, the editor (`ImageRenderer`) and Settings (an unattached `NSHostingView`'s display cache) on fixture captures drawn in code. No window, no app launch; preferences go to a throwaway suite and history to a temporary folder.
- `Packages/ExhibitCore/Sources/ExhibitFixtures` (not a product): synthetic screenshots drawn with CoreText (`FakeUI.swift`, `SampleFixture.swift`), shared by the test targets and sample generators.
- Tests use Swift Testing. Goldens live in `Tests/ExhibitCoreTests/Goldens`, drawn over the shared fixtures.

## Rules

- **Redaction is a security invariant.** Output pixels under a blur must never depend on original pixels under any blur. `RedactionTests` must stay green; never weaken it to make a change pass.
- **Exports are flat.** One image, no layers, no metadata, no copy of the original.
- **Deterministic rendering.** Same inputs, same bytes. No randomness except grain seeded by geometry.
- **Offscreen only.** Never launch, activate or show an app or window, and never capture the screen in tests or tooling. Fixtures are drawn in code.
- **Zero telemetry.** No network calls in the core.
- **Copy:** no em dashes anywhere user-facing or in docs. Say "free, source available", never "open source". No personal information in the repo; fixtures use `example.com` addresses and made-up keys.
- **Git:** small atomic commits, one logical change each, tests passing at every commit. Feature branches into `development`.
- **CI:** none for now (private repo; macOS runners cost money).
