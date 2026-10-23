#!/bin/sh
# Builds PitchTap.zip for a release and prints the <item> to add at the top of ../appcast.xml.
# Needs the Sparkle EdDSA private key in the login keychain (generate_keys) and the signing certificate.
# Order: ./release.sh → gh release create vX.Y.Z PitchTap.zip … → add the item to appcast.xml → commit, push.
set -e
cd "$(dirname "$0")"
./build-app.sh
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Info.plist)
BUILD=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" Info.plist)
MIN_OS=$(/usr/libexec/PlistBuddy -c "Print LSMinimumSystemVersion" Info.plist)
rm -f PitchTap.zip
ditto -c -k --sequesterRsrc --keepParent .build/PitchTap.app PitchTap.zip
SIGNATURE=$(.build/artifacts/sparkle/Sparkle/bin/sign_update PitchTap.zip)
cat <<EOF

Built $(pwd)/PitchTap.zip. Appcast item for $VERSION (fill in the notes):

    <item>
      <title>PitchTap $VERSION</title>
      <pubDate>$(LC_ALL=C TZ=UTC date -R)</pubDate>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$MIN_OS</sparkle:minimumSystemVersion>
      <description><![CDATA[<ul><li>…</li></ul>]]></description>
      <enclosure url="https://github.com/gkudva96/pitchtap/releases/download/v$VERSION/PitchTap.zip"
                 type="application/octet-stream" $SIGNATURE/>
    </item>
EOF
