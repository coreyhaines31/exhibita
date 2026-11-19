#!/bin/bash
# Builds, signs, notarizes, and publishes a release. Modelled on Kill Cord's and Fuel Gauge's scripts.
#
#   Scripts/release.sh 1.0.0               # everything, then asks before publishing
#   Scripts/release.sh --publish 1.0.0     # publishes without asking
#   Scripts/release.sh --dry-run 0.1.0     # local only: see below
#
# --dry-run runs the preflight checks (branch, clean tree and key are warnings instead of errors), the tests and
# lint, a Release archive with signing turned off, an ad-hoc signature (inside out, hardened runtime), the checks on
# the bundled exhibit command, the DMG and the cask with its checksum. It never uses a real signing identity, never
# notarizes, never touches the Sparkle private key, and never creates a tag or release or pushes anything.
# RELEASE_BUILD_DIR and RELEASE_DERIVED_DATA move its output, for example into a temporary folder.
#
# Needs, one time (docs/release/RELEASING.md):
#   - Developer ID signing: either Xcode signed in to the team (cloud signing), or
#     ASC_KEY_PATH + ASC_KEY_ID + ASC_ISSUER_ID for an App Store Connect API key (CI)
#   - notarytool credentials: either `xcrun notarytool store-credentials midnightoil-notary`
#     or APPLE_ID + APPLE_APP_PASSWORD (+ TEAM_ID) in the environment (CI)
#   - the Sparkle EdDSA private key in the keychain under the "exhibita" account, or
#     SPARKLE_KEY_FILE pointing at it (CI), and its public key as SPARKLE_PUBLIC_ED_KEY in project.yml
#   - gh authenticated with push access to coreyhaines31/exhibita and coreyhaines31/homebrew-tap
# No secret belongs in this file. Everything sensitive comes from the keychain or the environment.
set -euo pipefail

DRY_RUN=0
PUBLISH=0
VERSION=""
for ARG in "$@"; do
  case "$ARG" in
    --dry-run) DRY_RUN=1 ;;
    --publish) PUBLISH=1 ;;
    -*) echo "✗ Unknown option $ARG" >&2; exit 1 ;;
    *) VERSION="$ARG" ;;
  esac
done
if ! echo "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  echo "usage: Scripts/release.sh [--dry-run] [--publish] <major.minor.patch>" >&2
  exit 1
fi
if [ "$DRY_RUN" = 1 ] && [ "$PUBLISH" = 1 ]; then
  echo "✗ --dry-run never publishes; drop --publish" >&2
  exit 1
fi

cd "$(dirname "$0")/.."
TEAM_ID="${TEAM_ID:-KPQU8X839X}"
NOTARY_PROFILE="${NOTARY_PROFILE:-midnightoil-notary}"
REPO="coreyhaines31/exhibita"
APP_NAME="Exhibit A"
DMG_NAME="ExhibitA"
CASK="exhibit-a"
SITE="https://exhibitaformac.com"
SPARKLE_ACCOUNT="exhibita"
CLI_NAME="exhibit"
BUILD="${RELEASE_BUILD_DIR:-build/release}"
DERIVED="${RELEASE_DERIVED_DATA:-build/DerivedData}"

fail() { echo "✗ $*" >&2; exit 1; }
# A dry run reports what a real release would refuse, and carries on.
refuse() {
  if [ "$DRY_RUN" = 1 ]; then echo "  ! (dry run, would stop a release) $*"; else fail "$*"; fi
}
# Read whole before grep -q, so an early exit can't fail the pipe under pipefail.
signature() { local OUT; OUT=$(codesign -d --verbose=2 "$1" 2>&1); echo "$OUT"; }
quiet() { grep -E "error:|warning: |\*\* " || true; }
# xcodebuild may rewrite the package's Package.resolved with the app's packages.
restore_resolved() { git checkout -q -- Packages/ExhibitCore/Package.resolved 2>/dev/null || true; }

# Needs the full Xcode, even if the shell points DEVELOPER_DIR at the Command Line Tools.
case "${DEVELOPER_DIR:-}" in
  ""|*CommandLineTools*) export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ;;
esac

echo "▶ Preflight"
[ "$(git branch --show-current)" = "main" ] \
  || refuse "Release from main (in a separate worktree: git worktree add ../exhibita-release main)"
[ -z "$(git status --porcelain)" ] || refuse "Release requires a clean worktree"
TOOLS="git xcodegen xcodebuild swiftlint swift codesign lipo hdiutil shasum ditto"
[ "$DRY_RUN" = 1 ] || TOOLS="$TOOLS gh trash"
for TOOL in $TOOLS; do
  command -v "$TOOL" >/dev/null || fail "$TOOL is not installed"
done
[ "$DRY_RUN" = 1 ] || xcrun --find notarytool >/dev/null || fail "notarytool is missing from Xcode"
if git rev-parse -q --verify "refs/tags/v$VERSION" >/dev/null; then
  fail "v$VERSION is already tagged"
fi
if [ "$DRY_RUN" = 0 ]; then
  if git ls-remote --exit-code --tags origin "refs/tags/v$VERSION" >/dev/null 2>&1; then
    fail "v$VERSION is already tagged on origin"
  fi
  if gh release view "v$VERSION" --repo "$REPO" >/dev/null 2>&1; then
    fail "A v$VERSION release already exists"
  fi
fi
if grep -q "REPLACE_WITH_SPARKLE_PUBLIC_ED_KEY" project.yml; then
  refuse "Set SPARKLE_PUBLIC_ED_KEY in project.yml first (docs/release/RELEASING.md)"
fi
# The CLI reports CLI.version; the app's version is passed to xcodebuild below. Scripts/set-version.sh moves both.
CLI_VERSION=$(sed -n 's/.*public static let version = "\(.*\)"/\1/p' Packages/ExhibitCore/Sources/ExhibitCLI/Commands.swift)
[ "$CLI_VERSION" = "$VERSION" ] \
  || fail "CLI.version is $CLI_VERSION, not $VERSION: run Scripts/set-version.sh $VERSION on development first"

if [ -d "$BUILD" ]; then
  if command -v trash >/dev/null; then trash "$BUILD"; else fail "$BUILD exists; move it to the Trash first"; fi
fi
mkdir -p "$BUILD"
BUILD_NUMBER=$(git rev-list --count HEAD)

if [ -n "${APPLE_ID:-}" ]; then
  NOTARY_ARGS=(--apple-id "$APPLE_ID" --team-id "$TEAM_ID" --password "$APPLE_APP_PASSWORD")
else
  NOTARY_ARGS=(--keychain-profile "$NOTARY_PROFILE")
fi
# macOS ships bash 3.2, where expanding an empty array trips `set -u`; hence the ${arr[@]+...} form below.
# The keychain holds more than one app's key, so name this app's account explicitly.
SPARKLE_KEY_ARGS=(--account "$SPARKLE_ACCOUNT")
[ -n "${SPARKLE_KEY_FILE:-}" ] && SPARKLE_KEY_ARGS=(--ed-key-file "$SPARKLE_KEY_FILE")
# Cloud-managed Developer ID signing needs an account: Xcode's signed-in one, or an API key.
AUTH_ARGS=(-allowProvisioningUpdates)
if [ -n "${ASC_KEY_PATH:-}" ]; then
  AUTH_ARGS+=(-authenticationKeyPath "$ASC_KEY_PATH" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID")
fi
# A dry run archives unsigned and signs ad hoc afterwards.
SIGN_ARGS=(DEVELOPMENT_TEAM="$TEAM_ID" "${AUTH_ARGS[@]}")
[ "$DRY_RUN" = 1 ] && SIGN_ARGS=(CODE_SIGNING_ALLOWED=NO)

echo "▶ Linting"
swiftlint --strict --quiet

echo "▶ Testing ExhibitCore"
(cd Packages/ExhibitCore && swift test --quiet) > "$BUILD/swift-test.log" 2>&1 \
  || fail "ExhibitCore tests failed; see $BUILD/swift-test.log"

echo "▶ Generating project"
xcodegen generate --quiet

echo "▶ Testing the app's views (offscreen renders)"
xcodebuild -project ExhibitA.xcodeproj -scheme ExhibitA -derivedDataPath "$DERIVED" CODE_SIGNING_ALLOWED=NO \
  test > "$BUILD/app-test.log" 2>&1 || { restore_resolved; fail "ExhibitAViewTests failed; see $BUILD/app-test.log"; }
restore_resolved

echo "▶ Archiving $APP_NAME $VERSION ($BUILD_NUMBER)"
xcodebuild -project ExhibitA.xcodeproj -scheme ExhibitA -configuration Release \
  -archivePath "$BUILD/ExhibitA.xcarchive" \
  -derivedDataPath "$DERIVED" \
  ONLY_ACTIVE_ARCH=NO \
  "${SIGN_ARGS[@]}" \
  MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  archive > "$BUILD/archive.log" 2>&1 || { restore_resolved; quiet < "$BUILD/archive.log"; fail "Archive failed"; }
restore_resolved

if [ "$DRY_RUN" = 1 ]; then
  echo "▶ Signing ad hoc, inside out (dry run: no Developer ID)"
  APP="$BUILD/export/$APP_NAME.app"
  mkdir -p "$BUILD/export"
  ditto "$BUILD/ExhibitA.xcarchive/Products/Applications/$APP_NAME.app" "$APP"
  codesign --force --sign - --options runtime --timestamp=none "$APP/Contents/MacOS/$CLI_NAME"
  codesign --force --deep --sign - --options runtime --timestamp=none "$APP/Contents/Frameworks/Sparkle.framework"
  codesign --force --sign - --options runtime --timestamp=none --entitlements App/ExhibitA.entitlements "$APP"
else
  echo "▶ Exporting with Developer ID"
  cat > "$BUILD/export.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>developer-id</string>
  <key>teamID</key><string>$TEAM_ID</string>
  <key>signingStyle</key><string>automatic</string>
</dict></plist>
PLIST
  xcodebuild -exportArchive -archivePath "$BUILD/ExhibitA.xcarchive" \
    -exportOptionsPlist "$BUILD/export.plist" -exportPath "$BUILD/export" \
    "${AUTH_ARGS[@]}" | quiet
  APP="$BUILD/export/$APP_NAME.app"
fi
codesign --verify --deep --strict --verbose=1 "$APP"

echo "▶ Checking the bundle"
TOOL="$APP/Contents/MacOS/$CLI_NAME"
[ -x "$TOOL" ] || fail "The app is missing the $CLI_NAME command"
for BINARY in "$APP/Contents/MacOS/$APP_NAME" "$TOOL"; do
  ARCHS=$(lipo -archs "$BINARY")
  case " $ARCHS " in *" arm64 "*) ;; *) fail "$(basename "$BINARY") lacks arm64 ($ARCHS)" ;; esac
  case " $ARCHS " in *" x86_64 "*) ;; *) fail "$(basename "$BINARY") lacks x86_64 ($ARCHS)" ;; esac
  # Notarization rejects any executable without the hardened runtime.
  signature "$BINARY" | grep -q "flags=.*runtime" \
    || fail "$(basename "$BINARY") is not signed with the hardened runtime"
done
# The Homebrew cask and Settings link this onto the PATH.
[ "$("$TOOL" --version)" = "$VERSION" ] || fail "The $CLI_NAME command reports $("$TOOL" --version), not $VERSION"
# Without this the hardened runtime blocks the microphone, and dictation hears nothing.
ENTITLEMENTS=$(codesign -d --entitlements - "$APP" 2>/dev/null)
echo "$ENTITLEMENTS" | grep -q "com.apple.security.device.audio-input" \
  || fail "The app is missing the audio-input entitlement"
INFO="$APP/Contents/Info.plist"
[ "$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INFO")" = "$VERSION" ] \
  || fail "The app's version isn't $VERSION"
FEED=$(/usr/libexec/PlistBuddy -c "Print :SUFeedURL" "$INFO")
[ "$FEED" = "https://github.com/$REPO/releases/latest/download/appcast.xml" ] || fail "Unexpected SUFeedURL $FEED"
if [ "$DRY_RUN" = 0 ]; then
  signature "$TOOL" | grep -q "Authority=Developer ID Application" \
    || fail "The $CLI_NAME command isn't signed with Developer ID"
fi

if [ "$DRY_RUN" = 0 ]; then
  echo "▶ Notarizing the app"
  ditto -c -k --keepParent "$APP" "$BUILD/app.zip"
  xcrun notarytool submit "$BUILD/app.zip" "${NOTARY_ARGS[@]}" --wait
  xcrun stapler staple "$APP"
fi

echo "▶ Building the DMG"
DMG="$BUILD/$DMG_NAME-$VERSION.dmg"
STAGE="$BUILD/dmg"
mkdir -p "$STAGE" && cp -R "$APP" "$STAGE/" && ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO -quiet "$DMG"
if [ "$DRY_RUN" = 1 ]; then
  hdiutil verify -quiet "$DMG"
else
  # The DMG is signed when a local Developer ID identity exists; with cloud-managed
  # signing there is none, and notarization accepts an unsigned DMG of a signed app.
  if security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
    codesign --sign "Developer ID Application" --timestamp "$DMG"
  fi
  xcrun notarytool submit "$DMG" "${NOTARY_ARGS[@]}" --wait
  xcrun stapler staple "$DMG"
  # Gatekeeper judges the app inside the image, so that's what we assess. -nobrowse keeps it out of Finder.
  MOUNT=$(mktemp -d)
  hdiutil attach -nobrowse -quiet "$DMG" -mountpoint "$MOUNT"
  spctl --assess --type exec -v "$MOUNT/$APP_NAME.app"
  hdiutil detach -quiet "$MOUNT"
fi

echo "▶ Signing the update and writing the appcast"
# On a fresh checkout the packages folder doesn't exist yet; find's error must not stop the script.
SPARKLE_BIN=$(find "$DERIVED/SourcePackages/artifacts" -type d -path "*Sparkle/bin" 2>/dev/null | head -1 || true)
if [ -z "$SPARKLE_BIN" ]; then
  xcodebuild -project ExhibitA.xcodeproj -scheme ExhibitA -derivedDataPath "$DERIVED" \
    -resolvePackageDependencies -quiet
  restore_resolved
  SPARKLE_BIN=$(find "$DERIVED/SourcePackages/artifacts" -type d -path "*Sparkle/bin" 2>/dev/null | head -1 || true)
fi
[ -x "$SPARKLE_BIN/generate_appcast" ] || fail "Sparkle's generate_appcast wasn't found"
mkdir -p "$BUILD/appcast" && cp "$DMG" "$BUILD/appcast/"
if [ "$DRY_RUN" = 1 ]; then
  echo "  (dry run: generate_appcast found at $SPARKLE_BIN, not run; it needs the private key)"
else
  "$SPARKLE_BIN/generate_appcast" ${SPARKLE_KEY_ARGS[@]+"${SPARKLE_KEY_ARGS[@]}"} \
    --download-url-prefix "https://github.com/$REPO/releases/download/v$VERSION/" \
    --link "$SITE" \
    "$BUILD/appcast"
fi

echo "▶ Writing the cask"
SHA=$(shasum -a 256 "$DMG" | cut -d' ' -f1)
CASK_OUT="$BUILD/$CASK.rb"
sed -e "s/^  version \".*\"/  version \"$VERSION\"/" -e "s/^  sha256 \".*\"/  sha256 \"$SHA\"/" \
  "Scripts/homebrew/$CASK.rb" > "$CASK_OUT"
if ! grep -q "^  version \"$VERSION\"" "$CASK_OUT" || ! grep -q "^  sha256 \"$SHA\"" "$CASK_OUT"; then
  fail "Couldn't write the version and checksum into the cask"
fi

if [ "$DRY_RUN" = 1 ]; then
  echo "✓ Dry run of $APP_NAME $VERSION finished. Nothing was notarized or published."
  echo "  App:  $APP"
  echo "  DMG:  $DMG ($SHA)"
  echo "  Cask: $CASK_OUT"
  exit 0
fi

if [ "$PUBLISH" = 0 ]; then
  echo "Ready to publish $APP_NAME $VERSION: tag v$VERSION on main, a GitHub release with the DMG and appcast,"
  echo "and the $CASK cask in coreyhaines31/homebrew-tap."
  read -r -p "Type publish to continue, anything else to stop here: " ANSWER
  [ "$ANSWER" = "publish" ] || { echo "Stopped before publishing. Everything is in $BUILD."; exit 0; }
fi

echo "▶ Publishing GitHub release v$VERSION"
# A copy without the version in its name, so releases/latest/download/ExhibitA.dmg always works.
cp "$DMG" "$BUILD/$DMG_NAME.dmg"
gh release create "v$VERSION" "$DMG" "$BUILD/$DMG_NAME.dmg" "$BUILD/appcast/appcast.xml" \
  --repo "$REPO" --target main --title "$APP_NAME $VERSION" --generate-notes --latest

echo "▶ Updating the Homebrew cask"
TAP="$BUILD/homebrew-tap"
gh repo clone coreyhaines31/homebrew-tap "$TAP" -- --quiet --depth 1
CASK_FILE="$TAP/Casks/$CASK.rb"
# The first release adds the cask from Scripts/homebrew; later ones only move the version and checksum, so edits
# made in the tap stay.
mkdir -p "$TAP/Casks"
[ -f "$CASK_FILE" ] || cp "Scripts/homebrew/$CASK.rb" "$CASK_FILE"
sed -i '' -e "s/^  version \".*\"/  version \"$VERSION\"/" -e "s/^  sha256 \".*\"/  sha256 \"$SHA\"/" "$CASK_FILE"
git -C "$TAP" add "Casks/$CASK.rb"
git -C "$TAP" commit -qm "$CASK $VERSION" && git -C "$TAP" push -q
echo "✓ Released $APP_NAME $VERSION"
