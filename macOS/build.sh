#!/usr/bin/env bash
# Builds Sightline Prompter, packages it as an app bundle, ad-hoc signs it and installs it to /Applications.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"

# Build output stays outside the source tree.
SCRATCH="$HOME/Library/Caches/SightlinePrompter/build"
BIN="$SCRATCH/release/SightlinePrompter"
APP="/Applications/Sightline Prompter.app"

echo "==> Building (release)..."
mkdir -p "$SCRATCH"
# SIGHTLINE_DEV opens every Pro feature in this local build. macOS/appstore.sh does not set it.
swift build -c release --product SightlinePrompter --scratch-path "$SCRATCH" -Xswiftc -DSIGHTLINE_DEV

echo "==> Stopping the running copy..."
pkill -x SightlinePrompter || true
while pgrep -x SightlinePrompter >/dev/null; do sleep 0.2; done

echo "==> Creating app bundle: $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/SightlinePrompter"
cp "$ROOT/macOS/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/macOS/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

echo "==> Ad-hoc signing..."
codesign --force --sign - --deep "$APP"

echo "==> Launching..."
open "$APP"
echo "==> Done."
