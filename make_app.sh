#!/bin/bash
# 릴리스 빌드 후 FMRadio.app 번들을 만든다. (마이크 권한 요청이 앱 이름으로 표시됨)
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
codesign --force --sign - "$APP"
touch "$APP"   # Finder/Dock이 아이콘을 다시 읽도록

echo "완료: $APP"
echo "실행: open \"$APP\""
