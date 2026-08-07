#!/usr/bin/env bash
set -euo pipefail

# Generates Citadel / Fortress AppIcon sizes from Resources/AppIcon-master.png
# into Resources/Assets.xcassets/AppIcon.appiconset/

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MASTER="$ROOT/Resources/AppIcon-master.png"
ICONSET_DIR="$ROOT/Resources/Assets.xcassets/AppIcon.appiconset"

if [[ ! -f "$MASTER" ]]; then
  echo "Missing master icon: $MASTER" >&2
  exit 1
fi

mkdir -p "$ICONSET_DIR"
TMP="$(mktemp -d)"
OUT_1024="$TMP/icon_1024.png"

sips -z 1024 1024 "$MASTER" --out "$OUT_1024" >/dev/null

generate() {
  sips -z "$1" "$1" "$OUT_1024" --out "$ICONSET_DIR/$2" >/dev/null
}

generate 16  icon_16x16.png
generate 32  icon_16x16@2x.png
generate 32  icon_32x32.png
generate 64  icon_32x32@2x.png
generate 128 icon_128x128.png
generate 256 icon_128x128@2x.png
generate 256 icon_256x256.png
generate 512 icon_256x256@2x.png
generate 512 icon_512x512.png
cp "$OUT_1024" "$ICONSET_DIR/icon_512x512@2x.png"

rm -rf "$TMP"
echo "Icon generated at $ICONSET_DIR (from $MASTER)"
