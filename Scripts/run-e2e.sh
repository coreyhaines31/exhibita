#!/bin/bash
# Runs the app-hosted end-to-end tests (ExhibitAE2ETests) inside the real Exhibit A app, signed for Debug with the
# project's automatic signing. The app shows its windows while the tests run and quits when they finish.
#
#   Scripts/run-e2e.sh                 # build, then test
#   Scripts/run-e2e.sh -only-testing:ExhibitAE2ETests/BootTests   # extra xcodebuild arguments pass through
#
# Throwaway state only: history, the policy file and the bridge socket go to a new temporary support directory
# (EXHIBIT_SUPPORT_DIR) and settings to a new defaults suite (EXHIBIT_DEFAULTS_SUITE), both removed afterwards. The
# real app's settings file is checked before and after; the run fails if it changed. Refuses to start while the
# installed Exhibit A is running, rather than quitting it.
#
# CaptureTests take real captures and run only from Scripts/run-e2e-capture.sh (EXHIBIT_E2E_ALLOW_CAPTURE=1); here
# the app reads Screen Recording as off and they are left out.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1
# Xcode, not Command Line Tools: xcodebuild and the test host need it.
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

if pgrep -f "Exhibit A.app/Contents/MacOS" >/dev/null; then
    echo "Exhibit A is running. Quit it first; this script never quits it for you." >&2
    pgrep -fl "Exhibit A.app/Contents/MacOS" >&2
    exit 3
fi

LOGS="$ROOT/build/e2e"
mkdir -p "$LOGS"
TOKEN="$(uuidgen | cut -c1-8 | tr 'A-Z' 'a-z')"
# Short: the bridge socket's whole path must fit in 104 bytes.
SUPPORT="$(mktemp -d "${TMPDIR:-/tmp}/xa-e2e-$TOKEN")"
SUITE="com.exhibitaformac.e2e.$TOKEN"
REAL_PREFS="$HOME/Library/Preferences/com.exhibitaformac.ExhibitA.plist"
# The test host is the same app under its own bundle identifier, so its own settings (the save panel writes some)
# land in a domain of their own, removed afterwards.
HOST_DOMAIN="com.exhibitaformac.ExhibitA.e2e"
prefs_hash() { if [ -f "$REAL_PREFS" ]; then shasum "$REAL_PREFS" | cut -d' ' -f1; else echo none; fi; }
BEFORE="$(prefs_hash)"

cleanup() {
    pkill -f "$ROOT/build/E2EDerivedData/.*/Exhibit A.app/Contents/MacOS/Exhibit A" 2>/dev/null
    for domain in "$SUITE" "$HOST_DOMAIN"; do
        defaults delete "$domain" >/dev/null 2>&1
        [ -f "$HOME/Library/Preferences/$domain.plist" ] && trash "$HOME/Library/Preferences/$domain.plist"
    done
    [ -d "$SUPPORT" ] && trash "$SUPPORT"
    git -C "$ROOT" checkout -- Packages/ExhibitCore/Package.resolved 2>/dev/null
}
trap cleanup EXIT

# The `exhibit` binary the bridge tests run.
(cd Packages/ExhibitCore && swift build -c release --product exhibit >"$LOGS/cli-build.log" 2>&1)
status=$?
if [ $status -ne 0 ]; then echo "swift build failed ($status); see $LOGS/cli-build.log" >&2; exit $status; fi
EXHIBIT_BIN="$ROOT/Packages/ExhibitCore/.build/release/exhibit"

xcodegen generate >"$LOGS/xcodegen.log" 2>&1 || { echo "xcodegen failed; see $LOGS/xcodegen.log" >&2; exit 1; }

ALLOW_CAPTURE="${EXHIBIT_E2E_ALLOW_CAPTURE:-0}"
if [ "$ALLOW_CAPTURE" = "1" ]; then
    SELECTION=(-only-testing:ExhibitAE2ETests/CaptureTests)
else
    ALLOW_CAPTURE=0
    SELECTION=(-skip-testing:ExhibitAE2ETests/CaptureTests)
fi

start=$(date +%s)
# TEST_RUNNER_ variables reach the test host, the app itself, with the prefix removed.
TEST_RUNNER_EXHIBIT_SUPPORT_DIR="$SUPPORT" \
TEST_RUNNER_EXHIBIT_DEFAULTS_SUITE="$SUITE" \
TEST_RUNNER_EXHIBIT_E2E_CLI="$EXHIBIT_BIN" \
TEST_RUNNER_EXHIBIT_E2E_ALLOW_CAPTURE="$ALLOW_CAPTURE" \
xcodebuild -project ExhibitA.xcodeproj -scheme ExhibitAE2E -configuration Debug \
    -derivedDataPath build/E2EDerivedData EXHIBIT_E2E_BUNDLE_SUFFIX=.e2e test "${SELECTION[@]}" "$@" \
    >"$LOGS/test.log" 2>&1
status=$?
end=$(date +%s)

AFTER="$(prefs_hash)"
grep -E "Test Case .* (passed|failed|skipped)|E2E:|error:|XCTExpectFailure" "$LOGS/test.log" | sed 's/^/  /'
echo "xcodebuild test exit $status in $((end - start))s; log $LOGS/test.log"
if [ "$BEFORE" != "$AFTER" ]; then
    echo "The real app's settings file changed during the run." >&2
    [ $status -eq 0 ] && status=4
fi
exit $status
