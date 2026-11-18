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
  - `Planner.swift`: no-match, ambiguous, `--all`/`--nth`, one `MarkSpec` per command or `marks.json` entry. `Placement.swift`: arrow tails, text labels and step discs, scored against word boxes. `ApplyFile.swift`: `marks.json`. `Session.swift`: input, targets (reused from a bundle's document), output naming, writing.
  - Exit codes and error `code` strings are a public contract (`docs/cli.md`); change them only on purpose.
  - `MarkLayout` in ExhibitCore exposes the renderer's label, caption and disc sizes for placement.
- `Packages/ExhibitCore/Sources/ExhibitInterpret` (library, ExhibitCore only): spoken or typed instructions to operations. Text in, never the image.
  - `Contract.swift`: `InterpretRequest` (instruction, targets with secrets masked, optional pointer) to `InterpretOutcome` (`.understood(Interpretation)` with operations and `notFound`, or `.declined`). `TargetPick` is `.id`, `.kind` or `.text`, with the CLI selectors' meaning. `ChainedInterpreter` tries interpreters in order: grammar first, a model for what it declines.
  - `TargetListing.swift`: the list a model reads (`t1`, `t2`, ... refs; sensitive targets as "hidden"; fully masked duplicate lines dropped) and the target under the pointer. Models answer with refs only, never coordinates.
  - `Resolution.swift`: picks to targets, and `applyEntry(in:)` to a `marks.json` entry, so interpretations go through `apply`.
  - `GrammarInterpreter` (`Grammar*.swift`, `Words.swift`): verbs, kinds, pointer words, whole-line and close (mis-heard) text matches. Declines anything needing judgement, any unknown phrase, any tie and any qualified kind ("her email", "the payments key"); reports a kind with no targets as not found. Blur and highlight take every line holding the phrase (blur also substrings, wrapped lines and every close mis-hearing): an ambiguous redaction declines or over-covers, never under-covers (`GrammarRedactionTests`).
  - `ModelPrompt.swift`, `ModelEndpoint.swift`, `ModelInterpreter.swift`: the local model tier. Ollama (`/api/chat`) or OpenAI-compatible (`/v1/chat/completions`) on loopback only (`ModelEndpoint.isLoopback`; the transport checks again and refuses redirects). No structured output; refs not in the listing are dropped. `ModelTransport` is blocking so the CLI stays synchronous; tests inject a fake one. This is the only network code, and it never leaves the Mac.
- `Packages/ExhibitCore/Sources/ExhibitEval` (executable `exhibit-eval`, not shipped): the interpreter eval. `swift run exhibit-eval interpret [--file instructions.json] [--split dev|heldout|all|<split>] [--only grammar,model,model-alone,apple] [--model qwen3.8:27b]` scores the shipping grammar and the shipping chain (grammar, then `ModelInterpreter` only where it declined) on `eval/interpreter`; `swift run exhibit-eval speech` times on-device transcription of `say` audio. Apple's model (FoundationModels) and SpeechAnalyzer sit behind macOS 26 checks and are not shipped. Findings: `docs/product/spike-interpreter.md`, `docs/product/heldout2-results.md`. Tune on `instructions.json` only. `instructions-heldout2.json`, `HELDOUT2.md` and the `calendar`, `crm` and `ticket` fixtures are held out: do not read them while changing the interpreter, and do not tune on them.
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
