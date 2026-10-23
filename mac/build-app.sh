#!/bin/sh
# Builds PitchTap.app (release) next to this script, signed with the "PitchTap Self-Signed" certificate
# so the audio permission survives updates (SIGN_ID=… to use another; ad-hoc if it isn't in the keychain).
# SANDBOX=1 ./build-app.sh signs it with the App Sandbox (as the Mac App Store requires); updates won't work.
set -e
cd "$(dirname "$0")"
swift build -c release
APP=PitchTap.app
SIGN_ID="${SIGN_ID:-PitchTap Self-Signed}"
if ! security find-identity -p codesigning | grep -q "\"$SIGN_ID\""; then
  echo "warning: no \"$SIGN_ID\" signing identity; signing ad-hoc (users re-allow audio after each update)" >&2
  SIGN_ID=-
fi
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp .build/release/PitchTap "$APP/Contents/MacOS/PitchTap"
cp Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
ditto .build/release/Sparkle.framework "$APP/Contents/Frameworks/Sparkle.framework"

# Inside out: Sparkle's helpers, then the framework, then the app.
S="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
codesign --force --sign "$SIGN_ID" "$S/XPCServices/Installer.xpc"
codesign --force --sign "$SIGN_ID" --preserve-metadata=entitlements "$S/XPCServices/Downloader.xpc"
codesign --force --sign "$SIGN_ID" "$S/Autoupdate"
codesign --force --sign "$SIGN_ID" "$S/Updater.app"
codesign --force --sign "$SIGN_ID" "$APP/Contents/Frameworks/Sparkle.framework"
if [ "$SANDBOX" = 1 ]; then
  echo "warning: sandboxed build; Sparkle isn't set up for the sandbox, so updates won't work" >&2
  codesign --force --sign "$SIGN_ID" --entitlements PitchTap-Sandbox.entitlements "$APP"
else
  codesign --force --sign "$SIGN_ID" "$APP"
fi
echo "Built $(pwd)/$APP (signed: $SIGN_ID)"
