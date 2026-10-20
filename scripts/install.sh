#!/bin/bash
# Build a Release copy and install it to /Applications, so Accessibility permission
# stays attached to one stable app path and signature.
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="UDock Touch"
DEST="/Applications/$APP_NAME.app"

if [ ! -f Config/Local.xcconfig ]; then
    echo "Note: no Config/Local.xcconfig, so this is an ad-hoc signed build."
    echo "macOS will ask for Accessibility permission again after every rebuild."
    echo "See Config/Local.xcconfig.example to sign with your own certificate."
fi

xcodegen generate --quiet
xcodebuild -project UDockTouch.xcodeproj -scheme UDockTouch -configuration Release \
    -derivedDataPath build/DerivedData -quiet build

pkill -x "$APP_NAME" || true
if [ -d "$DEST" ]; then
    if command -v trash >/dev/null; then trash "$DEST"; else rm -rf "$DEST"; fi
fi
ditto "build/DerivedData/Build/Products/Release/$APP_NAME.app" "$DEST"
open "$DEST"
echo "Installed $DEST"
