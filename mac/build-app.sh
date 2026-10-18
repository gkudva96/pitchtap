#!/bin/sh
# Builds PitchTap.app (release, ad-hoc signed) next to this script.
# SANDBOX=1 ./build-app.sh signs it with the App Sandbox (as the Mac App Store requires).
set -e
cd "$(dirname "$0")"
swift build -c release
APP=PitchTap.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/PitchTap "$APP/Contents/MacOS/PitchTap"
cp Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
if [ "$SANDBOX" = 1 ]; then
  codesign --force --sign - --entitlements PitchTap-Sandbox.entitlements "$APP"
else
  codesign --force --sign - "$APP"
fi
echo "Built $(pwd)/$APP"
