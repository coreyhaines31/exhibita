#!/bin/bash
# Sets the version the app and the exhibit command report, on development before a release:
#
#   Scripts/set-version.sh 1.0.0
#
# The app's MARKETING_VERSION (project.yml) and CLI.version (ExhibitCLI/Commands.swift) move together, and
# Scripts/release.sh refuses a release whose CLI.version doesn't match. Commit the change, then merge to main.
set -euo pipefail

VERSION="${1:-}"
if ! echo "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  echo "usage: Scripts/set-version.sh <major.minor.patch>" >&2
  exit 1
fi
cd "$(dirname "$0")/.."
COMMANDS=Packages/ExhibitCore/Sources/ExhibitCLI/Commands.swift
sed -i '' -e "s/^    MARKETING_VERSION: \".*\"/    MARKETING_VERSION: \"$VERSION\"/" project.yml
sed -i '' -e "s/public static let version = \".*\"/public static let version = \"$VERSION\"/" "$COMMANDS"
grep -q "MARKETING_VERSION: \"$VERSION\"" project.yml || { echo "✗ project.yml wasn't updated" >&2; exit 1; }
grep -q "public static let version = \"$VERSION\"" "$COMMANDS" || { echo "✗ $COMMANDS wasn't updated" >&2; exit 1; }
echo "✓ Version $VERSION in project.yml and CLI.version"
