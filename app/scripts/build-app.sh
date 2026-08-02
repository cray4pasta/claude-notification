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

# SPM's generated Bundle.module accessor (for Sources/Nudge/Resources/*,
# e.g. companion GIFs) tries two paths in order: Bundle.main.bundleURL +
# "Nudge_Nudge.bundle" (the .app's own root), then a hardcoded absolute
# fallback straight into .build/.../release/Nudge_Nudge.bundle (see
# .build/.../DerivedSources/resource_bundle_accessor.swift).
#
# We deliberately do NOT copy the resource bundle into the .app: codesign
# rejects it either place we tried (Contents/MacOS -> "bundle format
# unrecognized", since it's plain copied files with no Info.plist, not a
# real CFBundle; the app's own root -> "unsealed contents present in the
# bundle root", since only Contents/ is allowed to live there). Instead we
# just let the accessor's absolute-path fallback do the job - it works
# because .build/ isn't cleaned between builds on this machine.
#
# Fragile by nature: breaks if this repo ever moves to a different path,
# or if .build gets wiped without a rebuild before the next launch. Fine
# for this single-machine personal tool; would need a real fix (e.g. a
# proper Info.plist inside the resource bundle so codesign accepts it, or
# an Xcode-generated bundle instead of hand-assembling) before this could
# ship to a second machine.

echo "Assembling $BUNDLE..."
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS"
cp "$BIN_PATH" "$BUNDLE/Contents/MacOS/Nudge"
cp "$PKG_DIR/Resources/Info.plist" "$BUNDLE/Contents/Info.plist"

echo "Ad-hoc code signing..."
codesign --force --sign - "$BUNDLE"

echo "Done: $BUNDLE"
echo "Run it with:  open \"$BUNDLE\""
