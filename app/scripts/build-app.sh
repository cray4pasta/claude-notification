#!/bin/bash
# Builds Nudge and assembles it into a minimal .app bundle. A plain SPM
# executable can't use UNUserNotificationCenter or behave as a proper menu
# bar app without an Info.plist + bundle identifier, so we do that step by
# hand rather than pulling in Xcode project generation.
set -euo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PKG_DIR="$APP_DIR/Nudge"
BUILD_DIR="$APP_DIR/build"
BUNDLE="$BUILD_DIR/Nudge.app"

echo "Building Nudge (release)..."
(cd "$PKG_DIR" && swift build -c release)

BIN_PATH="$PKG_DIR/.build/release/Nudge"
if [ ! -f "$BIN_PATH" ]; then
  echo "error: expected binary not found at $BIN_PATH" >&2
  exit 1
fi

echo "Assembling $BUNDLE..."
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS"
cp "$BIN_PATH" "$BUNDLE/Contents/MacOS/Nudge"
cp "$PKG_DIR/Resources/Info.plist" "$BUNDLE/Contents/Info.plist"

echo "Ad-hoc code signing..."
codesign --force --deep --sign - "$BUNDLE"

echo "Done: $BUNDLE"
echo "Run it with:  open \"$BUNDLE\""
