#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift test
swift build -c release
APP="dist/Anima Studio Public.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/AnimaStudio "$APP/Contents/MacOS/AnimaStudio"
cp StudioInfo.plist "$APP/Contents/Info.plist"
if [ -n "${ANIMA_SIGN_IDENTITY:-}" ]; then
  codesign --force --options runtime --timestamp --entitlements Config/Studio.entitlements --sign "$ANIMA_SIGN_IDENTITY" "$APP"
  codesign --verify --deep --strict "$APP"
else
  echo "Local development build. For distribution set ANIMA_SIGN_IDENTITY to your Developer ID and notarize."
fi
echo "$APP"
