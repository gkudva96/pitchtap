#!/bin/sh
# Renders the logo SVGs (via headless Chrome) into the Mac app icon and the extension icons.
#   logo.svg       full icon, macOS icon grid (app icon ≥ 64 px)
#   logo-small.svg no vibration arcs, bolder (app icon 16/32 px)
#   logo-tile.svg  small variant without the macOS margin (extension icons)
set -e
cd "$(dirname "$0")"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

render() { # svg → 1024 px png
  printf '<!doctype html><style>html,body{margin:0;background:transparent}</style>' > "$TMP/page.html"
  cat "$1" >> "$TMP/page.html"
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=1 \
    --default-background-color=00000000 --window-size=1024,1024 --user-data-dir="$TMP/profile" \
    --screenshot="$2" "file://$TMP/page.html" >/dev/null 2>&1
}
resize() { sips -z "$2" "$2" "$1" --out "$3" >/dev/null; }

render logo.svg "$TMP/full.png"
render logo-small.svg "$TMP/small.png"
render logo-tile.svg "$TMP/tile.png"
cp "$TMP/full.png" logo-1024.png

ICONSET="$TMP/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 64 128 256 512 1024; do
  src="$TMP/full.png"; [ "$size" -le 32 ] && src="$TMP/small.png"
  resize "$src" $size "$TMP/$size.png"
done
cp "$TMP/16.png" "$ICONSET/icon_16x16.png";      cp "$TMP/32.png" "$ICONSET/icon_16x16@2x.png"
cp "$TMP/32.png" "$ICONSET/icon_32x32.png";      cp "$TMP/64.png" "$ICONSET/icon_32x32@2x.png"
cp "$TMP/128.png" "$ICONSET/icon_128x128.png";   cp "$TMP/256.png" "$ICONSET/icon_128x128@2x.png"
cp "$TMP/256.png" "$ICONSET/icon_256x256.png";   cp "$TMP/512.png" "$ICONSET/icon_256x256@2x.png"
cp "$TMP/512.png" "$ICONSET/icon_512x512.png";   cp "$TMP/1024.png" "$ICONSET/icon_512x512@2x.png"
mkdir -p ../mac/Resources
iconutil -c icns "$ICONSET" -o ../mac/Resources/AppIcon.icns

for size in 16 32 48; do resize "$TMP/tile.png" $size ../extension/icons/$size.png; done
resize "$TMP/full.png" 128 ../extension/icons/128.png
echo "Wrote mac/Resources/AppIcon.icns, extension/icons/*.png, design/logo-1024.png"
