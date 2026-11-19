# Exhibit A

A Mac menu bar screenshot tool: mark up with single keys, a spoken sentence, or one CLI command from an agent. Free, source available, and everything runs on your Mac.

## Install

Needs macOS 14 or later.

```sh
brew install --cask coreyhaines31/tap/exhibit-a
```

Or download `ExhibitA.dmg` from the [latest release](https://github.com/coreyhaines31/exhibita/releases/latest). The app updates itself, and the cask puts the `exhibit` command on your PATH.

## Use

- **Capture and edit:** ⌥⇧4, drag a region (Space picks a window, ↩ takes the screen). The editor opens in place.
- **Capture to clipboard:** ⌃⌥⇧4. No window opens; the capture still lands in history.
- **Mark up with one key each:** A arrow, C circle, B blur, H highlight, T text, R box, N numbered step, ⇧B blur every detected secret. ↩ copies and closes. Those are the defaults: change any of them in Settings, Shortcuts.
- **Say it:** hold D and speak, for example "blur the emails and circle pricing".

Both hotkeys can be changed in Settings. Once macOS's own screenshot shortcuts are turned off, they become ⇧⌘4 and ⌃⇧⌘4.

## For agents

```sh
exhibit capture --window "Safari"
exhibit blur shot.png --kind email --kind key
exhibit arrow shot.png --to "Pricing" --label "Click here"
exhibit say shot.png "blur the emails and circle pricing"
exhibit mcp                                   # the same commands over MCP
```

Commands on image files need no app and no permissions. Live captures come from the running app, which never takes focus. Details are in [docs/cli.md](docs/cli.md).

## Privacy

No account and no telemetry. Text is read and speech is transcribed on your Mac with Apple's on-device frameworks. The app's only network call is the update check. Free-form instructions can use a local model you run yourself (an Ollama or LM Studio endpoint on this Mac).

## Building

```sh
cd Packages/ExhibitCore && swift build -c release   # .build/release/exhibit
xcodegen generate && open ExhibitA.xcodeproj        # the app
```

## License

[FSL-1.1-MIT](LICENSE) © Corey Haines. Free to use and modify, including at work. You can't resell it or build a competing product from it. Each release becomes MIT two years after it ships. Paid cloud and Teams code will live in `ee/` under its own [commercial licence](ee/LICENSE). See also [TRADEMARK.md](TRADEMARK.md) and [CONTRIBUTING.md](CONTRIBUTING.md).
