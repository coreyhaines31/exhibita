# Releasing

For maintainers. Exhibit A ships the way its siblings do: a notarized DMG on a GitHub release, Sparkle updates from the appcast attached to that release, and a cask in `coreyhaines31/homebrew-tap`. `Scripts/release.sh` is modelled on Kill Cord's and Fuel Gauge's.

Signing, notarization and publication have never been run for Exhibit A. Only `--dry-run` has. The first real release is also the rehearsal: run it without `--publish` so it stops at the prompt, check the DMG on a second Mac (`docs/product/unit10-live-checklist.md`), then publish.

## Cutting a release

1. On `development`, set the version and merge to `main` through a pull request:

   ```sh
   Scripts/set-version.sh 0.1.0          # project.yml MARKETING_VERSION and CLI.version together
   ```

2. Release from a separate worktree of `main`, so work in progress can't leak into the build:

   ```sh
   git worktree add ../exhibita-release main
   cd ../exhibita-release
   Scripts/release.sh 0.1.0              # asks before publishing
   Scripts/release.sh --publish 0.1.0    # publishes without asking
   ```

The script:

1. **Preflight.** Refuses unless it is on `main` with a clean tree, every tool is installed, `v<version>` is tagged neither locally nor on `origin` and has no release, `SPARKLE_PUBLIC_ED_KEY` is set, and `CLI.version` equals the version. Runs `swiftlint --strict`, the ExhibitCore tests and the app's `ExhibitAViewTests` (view models and offscreen renders; renders are not compared with `docs/samples/app`, the same as the siblings).
2. **Archive.** A Release archive, universal (`arm64 x86_64`, `ONLY_ACTIVE_ARCH=NO`), hardened runtime, team `KPQU8X839X`, version from the argument and build number from the commit count, so it always goes up.
3. **Export with Developer ID** (cloud-managed signing, so no certificate lives on the machine). The `exhibit` command is an Xcode tool target compiled from the package's own `Sources/exhibit/main.swift`; Xcode signs it on copy into `Contents/MacOS` before it signs the app, so nesting is right for notarization.
4. **Checks the bundle.** Both executables universal and hardened; `exhibit --version` prints the version; the command is signed by Developer ID; the app has the microphone entitlement, the right version and the right `SUFeedURL`.
5. **Notarizes and staples** the app, builds the DMG (`ExhibitA-<version>.dmg`), signs it when a local Developer ID identity exists, notarizes and staples it, and has Gatekeeper assess the app inside it.
6. **Sparkle.** `generate_appcast --account exhibita` signs the DMG and writes `appcast.xml`.
7. **Cask.** Writes `exhibit-a.rb` with the version and checksum.
8. **Publishes** (after typing `publish`, or straight away with `--publish`): `gh release create v<version>` on `main` with the DMG, an unversioned `ExhibitA.dmg` and `appcast.xml`, then the cask commit to `coreyhaines31/homebrew-tap` (copied from `Scripts/homebrew/exhibit-a.rb` the first time; later releases change only the version and checksum).

Nothing is tagged or pushed before step 8.

## Dry run

```sh
RELEASE_BUILD_DIR=/tmp/exhibita-dry/release RELEASE_DERIVED_DATA=/tmp/exhibita-dry/DerivedData \
  Scripts/release.sh --dry-run 0.1.0
```

Runs everything local: the preflight (branch, clean tree and Sparkle key become warnings), lint and tests, a Release archive with signing turned off, an ad-hoc signature applied inside out with the hardened runtime and the app's entitlements, every bundle check except the Developer ID authority, the DMG (`hdiutil verify`), finding Sparkle's tools, and the cask with the DMG's checksum. It never uses a signing identity, never notarizes, never reads the Sparkle private key, and never tags, releases or pushes.

## One-time setup (Corey)

- **Sparkle key.** Generate this app's own key pair on the release Mac. The private key goes into the login Keychain and never leaves it:

  ```sh
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
  xcodegen generate && xcodebuild -project ExhibitA.xcodeproj -scheme ExhibitA -derivedDataPath build/DerivedData \
    -resolvePackageDependencies -quiet
  "$(find build/DerivedData/SourcePackages/artifacts -type d -path '*Sparkle/bin' | head -1)/generate_keys" \
    --account exhibita
  ```

  It prints the public key. Put it in `project.yml` as `SPARKLE_PUBLIC_ED_KEY` (replacing `REPLACE_WITH_SPARKLE_PUBLIC_ED_KEY`) and commit that on `development`. Run `generate_keys --account exhibita -p` later to print it again. Never use another app's account, and never export the private key into the repo. Until the key is set, the updater never starts and Check for Updates is disabled.
- **Developer ID.** Xcode signed in to team `KPQU8X839X` (Settings, Accounts), as for the siblings, or `ASC_KEY_PATH`, `ASC_KEY_ID` and `ASC_ISSUER_ID` for an App Store Connect API key. The bundle ids `com.exhibitaformac.ExhibitA` and `com.exhibitaformac.ExhibitA.CLI` need no registration for Developer ID; cloud signing creates what it needs on first export.
- **Notarization.** The siblings share one notarytool profile, `midnightoil-notary`, which the script uses by default. Confirm it exists with `xcrun notarytool history --keychain-profile midnightoil-notary`. Pass `NOTARY_PROFILE=<name>` to use another.
- **Where the appcast is served.** The app checks `https://github.com/coreyhaines31/exhibita/releases/latest/download/appcast.xml`. GitHub serves release assets anonymously only from public repos, and `coreyhaines31/exhibita` is private, so before the first release either make the repo public (as every sibling is; the license is FSL-1.1-MIT, free and source available) or choose another public host for the DMG and appcast and change `SUFeedURL`, the cask `url` and the script's `--download-url-prefix` together. The Homebrew cask has the same need.
- **GitHub CLI.** `gh` signed in with push access to this repo and `coreyhaines31/homebrew-tap`.
- **Branch protection.** None: no sibling protects `main`. Releases come from `main`, which only takes merges from `development`.
- **App icon.** Not in this repo yet (mac-app-kit assigns it). Releasing without one ships the generic icon.

## Updates

Automatic checks are on by default (`SUEnableAutomaticChecks`), once a day, and can be turned off in Settings, General, where Check for Updates… also lives. This is the app's one network call besides the speech model macOS downloads for dictation; the Settings footer says so. Each release's appcast points at that release's DMG.

## When something goes wrong

- **notarytool hangs on "initiating connection":** if no entry shows in `xcrun notarytool history` after about 5 minutes, stop it and run the script again. Nothing is published before notarization finishes.
- **CLI.version doesn't match:** run `Scripts/set-version.sh <version>` on `development`, merge, and start again from `main`.
- **GitHub returns a 500 and leaves a draft:** `gh release edit v<version> --draft=false --latest`, then bump the cask by hand.
- **The cask push is rejected:** another release pushed first. Redo the cask bump in a fresh clone of the tap.
- **Release notes:** the script uses `--generate-notes`. Rewrite them by hand for people, not commits.
