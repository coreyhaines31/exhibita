#!/bin/bash
# Renders the panel, Settings and the editor on fixture data to docs/samples/app/*.png. Offscreen only: the unhosted
# ExhibitAViewTests bundle draws the views with ImageRenderer or an unattached hosting view. Exhibit A is
# never launched and no window is shown. Look at every changed image before committing it.
set -euo pipefail
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
root="$(cd "$(dirname "$0")/.." && pwd)"
out="$root/docs/samples/app"
mkdir -p "$out"
cd "$root"
xcodegen generate --quiet
# xcodebuild passes TEST_RUNNER_-prefixed variables into the test process without the prefix.
TEST_RUNNER_EXHIBIT_RENDER_DIR="$out" xcodebuild -project ExhibitA.xcodeproj -scheme ExhibitA \
  -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO \
  -only-testing:ExhibitAViewTests/PanelRenderTests/testRendersThePanel \
  -only-testing:ExhibitAViewTests/PanelRenderTests/testRendersSettings \
  -only-testing:ExhibitAViewTests/EditorRenderTests/testRendersTheEditor \
  test -quiet
ls -1 "$out"
