# Exhibit A

A free, source-available (FSL-1.1-MIT) macOS menu bar screenshot tool: mark up a capture with single keys, a spoken sentence, or one CLI command from an agent. Every capture is one document (original image, targets found in it, marks); hand, voice and CLI write the same marks, and one deterministic renderer flattens them. The product spec is `docs/product/spec.md`; the on-disk format is `docs/format.md`.

## Build and test

This machine's active developer directory is Command Line Tools, so prefix Swift commands:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd Packages/ExhibitCore && swift build && swift test
EXHIBIT_RECORD_GOLDENS=1 swift test   # rewrite goldens and docs/samples/*.png; look at every changed image
swiftlint --strict                     # from the repo root
```

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
  - Faces: `VNDetectFaceRectanglesRequest`.
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
