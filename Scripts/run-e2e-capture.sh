#!/bin/bash
# Runs CaptureTests: real captures of this Mac's screen through the selection overlay and the capture bridge,
# inside the Debug test host, on the same throwaway state as Scripts/run-e2e.sh (which this calls).
#
#   Scripts/run-e2e-capture.sh                  # all of CaptureTests
#   Scripts/run-e2e-capture.sh -only-testing:ExhibitAE2ETests/CaptureTests/testCancel   # one test
#
# Corey authorized this run for issue 35. The captures go only to the temporary support directory, which
# run-e2e.sh trashes afterwards; nothing is copied elsewhere and no picture is written. The tests never ask for
# Screen Recording: when the test host does not already have it, they skip. Windows and the overlay flash on
# every display while it runs.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REAL_CAPTURES="$HOME/Library/Application Support/Exhibit A/Captures"
listing() { if [ -d "$REAL_CAPTURES" ]; then ls -la "$REAL_CAPTURES" | shasum | cut -d' ' -f1; else echo none; fi; }
samples() { git -C "$ROOT" status --porcelain -- docs/samples | shasum | cut -d' ' -f1; }
CAPTURES_BEFORE="$(listing)"
SAMPLES_BEFORE="$(samples)"

EXHIBIT_E2E_ALLOW_CAPTURE=1 "$ROOT/Scripts/run-e2e.sh" "$@"
status=$?

if [ "$CAPTURES_BEFORE" != "$(listing)" ]; then
    echo "The real app's captures folder changed during the run." >&2
    [ $status -eq 0 ] && status=5
fi
if [ "$SAMPLES_BEFORE" != "$(samples)" ]; then
    echo "docs/samples changed during a capture run; live captures must never be written there." >&2
    [ $status -eq 0 ] && status=6
fi
exit $status
