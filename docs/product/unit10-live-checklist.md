# Unit 10 live checklist

Everything in unit 10 (release plumbing, issue 13) that only a person with a Developer ID, a notarization profile and a second Mac can check. The package tests (`CommandLineToolTests`), lint, the Debug and Release builds with signing off, the app tests, the offscreen renders in `docs/samples/app/settings-*.png` and `Scripts/release.sh --dry-run` passed. **Nothing below has been run**: no Developer ID signature, no notarization, no tag, no GitHub release, no cask, and the app was never launched.

Accepted when: a notarized DMG opens on a second Mac and updating from the previous build works (spec, Build units).

Before starting, do the one-time setup in `docs/release/RELEASING.md` (Sparkle key, notarytool profile, where the appcast is served). Write down the macOS version, the Mac (Apple silicon or Intel) and the version for every run.

## 1. Notarized DMG

| Step | Expected |
|---|---|
| `Scripts/release.sh 0.1.0` from a clean `main` worktree, answer anything but `publish` at the prompt | Every step through "Writing the cask" passes, including both notarizations and `spctl --assess` ("accepted, source=Notarized Developer ID"). It stops before publishing. |
| `codesign -dv --verbose=4 "build/release/export/Exhibit A.app/Contents/MacOS/exhibit"` | `Authority=Developer ID Application`, `flags=0x10000(runtime)`, identifier `com.exhibitaformac.ExhibitA.CLI`. |
| `xcrun stapler validate build/release/ExhibitA-0.1.0.dmg` | "The validate action worked!" |
| Copy the DMG to a second Mac that has never run Exhibit A (AirDrop or a download, so it gets the quarantine flag), open it, drag Exhibit A to Applications, open it | No "unidentified developer" or "damaged" dialog. The glyph appears in the menu bar. If you can, repeat on an Intel Mac. |
| On the second Mac, the panel and Settings | Panel opens. Settings, General shows "Version 0.1.0" and Check for Updates… enabled (it is disabled only while the Sparkle key is a placeholder). |

## 2. Launch at login (release build)

| Step | Expected |
|---|---|
| After the first launch from Applications on the second Mac, open System Settings, General, Login Items | Exhibit A is listed under Open at Login. Settings shows Launch at login on. |
| Restart or log out and back in | Exhibit A starts by itself; the hotkeys work. |
| Turn Launch at login off in Settings, log out and in | It does not start. Turning it on again lists it again. |

## 3. Command line tool

| Step | Expected |
|---|---|
| Settings, Command line, on a Mac without Homebrew's cask | "Command line tool" shows Link…. Press it: "Linked the exhibit command at /opt/homebrew/bin/exhibit" (or `/usr/local/bin`, or `~/.local/bin` with the PATH note). No password prompt. The row now shows Linked. |
| New Terminal window: `exhibit --version`, `which exhibit` | `0.1.0`; the path from the previous step. |
| `exhibit capture --screen` with Screen Recording allowed | A capture id and image path; the glyph blinks. (Bridge details: `docs/product/unit6-live-checklist.md`.) |
| Copy the MCP line, paste it into Terminal, then `claude mcp list` | `exhibit` is listed and connected; the path in the line is the linked one. |
| Put an unrelated file at the first folder's `exhibit` and press Link… on a fresh install | That file is left alone; the link goes to the next writable folder, or the footer says something else is there. |

## 4. Homebrew cask

| Step | Expected |
|---|---|
| After publishing: `brew update && brew install --cask coreyhaines31/tap/exhibit-a` on a Mac without Exhibit A | Installs `Exhibit A.app` and links `exhibit` (`brew info --cask exhibit-a` lists the binary). `exhibit --version` prints the version. Settings shows the command as Linked. |
| `brew audit --cask --online coreyhaines31/tap/exhibit-a` | No errors. |
| `brew uninstall --zap --cask exhibit-a` on a test Mac | The app, the `exhibit` link, `~/Library/Application Support/Exhibit A` (captures, `policy.json`, `Bridge/`) and the preferences file are gone. |

## 5. Update from the previous build

| Step | Expected |
|---|---|
| With 0.1.0 installed on the second Mac, release 0.1.1 (`Scripts/set-version.sh 0.1.1` on development, merge, release with `publish`) | The 0.1.1 release has `ExhibitA-0.1.1.dmg`, `ExhibitA.dmg` and `appcast.xml`; `curl -sL https://github.com/coreyhaines31/exhibita/releases/latest/download/appcast.xml` (logged out) returns the appcast with an `sparkle:edSignature`. |
| On the 0.1.0 Mac, Settings, General, Check for Updates… | Sparkle offers 0.1.1. Install and relaunch: Settings shows 0.1.1; history, marks and settings are intact; `exhibit --version` prints `0.1.1`. |
| Leave a second 0.1.0 Mac running a day with automatic checks on | It offers the update without being asked. With the switch off, it does not. |
| The cask after 0.1.1 | `brew upgrade --cask exhibit-a` is a no-op on the Sparkle-updated Mac (`auto_updates true`) and upgrades a fresh 0.1.0 install. |
