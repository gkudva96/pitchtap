#!/bin/sh
# Builds everything the Chrome Web Store needs into store/out/:
#   pitchtap-extension-<version>.zip   the package to upload
#   screenshot-1..4.png                1280×800 listing screenshots (the real popup, rendered by headless Chrome)
#   promo-tile.png                     440×280 small promo tile
set -e
cd "$(dirname "$0")/.."
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
OUT=store/out
TMP=$(mktemp -d)
PORT=8765
mkdir -p "$OUT"

# popup-preview.html uses fetch and ES modules, which need http:// rather than file://.
python3 -m http.server $PORT --bind 127.0.0.1 >/dev/null 2>&1 &
SERVER=$!
trap 'kill $SERVER 2>/dev/null; wait $SERVER 2>/dev/null; rm -rf "$TMP"' EXIT
sleep 1

shot() { # url width height out
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=1 \
    --virtual-time-budget=3000 --blink-settings=preferredColorScheme=1 --window-size="$2,$3" --user-data-dir="$TMP/profile" \
    --screenshot="$4" "http://127.0.0.1:$PORT/$1" >/dev/null 2>&1
}
for n in 1 2 3 4; do shot "store/scene.html?shot=$n" 1280 800 "$OUT/screenshot-$n.png"; done
shot store/promo-tile.html 440 280 "$OUT/promo-tile.png"

VERSION=$(python3 -c "import json; print(json.load(open('extension/manifest.json'))['version'])")
ZIP="$OUT/pitchtap-extension-$VERSION.zip"
rm -f "$ZIP"
(cd extension && zip -qr -X "../$ZIP" . -x '.*' -x '*/.*')
echo "Wrote $OUT: $(cd "$OUT" && ls | tr '\n' ' ')"
