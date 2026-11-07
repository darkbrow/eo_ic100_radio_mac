#!/bin/bash
# Build the release binary and assemble an FMRadio.app bundle.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/FMRadio"

APP="build/FMRadio.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/FMRadio"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp -R Resources/en.lproj Resources/ko.lproj "$APP/Contents/Resources/"
codesign --force --sign - "$APP"
touch "$APP"   # Refresh the Finder/Dock icon.

echo "Done: $APP"
echo "Run: open \"$APP\""
