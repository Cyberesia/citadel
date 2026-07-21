#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="${VERSION:-0.1.0}"
APP_BUNDLE="$ROOT/build/release/Build/Products/Release/Citadel.app"
DMG_DIR="$ROOT/build/dmg_staging"
DMG="$ROOT/artifacts/Citadel-${VERSION}.dmg"
SIGN_ID="${SIGN_ID:-Developer ID Application}"
NOTARY_PROFILE="${NOTARY_PROFILE:-citadel-notary}"

mkdir -p artifacts
rm -rf "$DMG_DIR"
mkdir -p "$DMG_DIR"
cp -R "$APP_BUNDLE" "$DMG_DIR/"
ln -s /Applications "$DMG_DIR/Applications"

rm -f "$DMG"
hdiutil create \
    -volname "Citadel ${VERSION}" \
    -srcfolder "$DMG_DIR" \
    -ov \
    -format UDZO \
    -fs HFS+ \
    "$DMG" >/dev/null

echo ">> Signing DMG…"
codesign --force --timestamp --sign "$SIGN_ID" "$DMG"

echo ">> Submitting DMG for notarization…"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait

echo ">> Stapling DMG…"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"

echo ">> Done: $DMG"
shasum -a 256 "$DMG"
