#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_BUNDLE="build/release/Build/Products/Release/Citadel.app"
TEAM_ID="${TEAM_ID:-}"
SIGN_ID="${SIGN_ID:-Developer ID Application}"
NOTARY_PROFILE="${NOTARY_PROFILE:-citadel-notary}"
APP_ENT="$ROOT/Sources/GUI/Citadel.entitlements"
HELPER_ENT="$ROOT/Sources/Helper/Helper.entitlements"
NETEXT_ENT="$ROOT/Sources/NetExt/NetExt.entitlements"
VERSION="${VERSION:-0.1.0}"

if [ -z "$TEAM_ID" ]; then
  echo "ERROR: set TEAM_ID (and optionally SIGN_ID / NOTARY_PROFILE) before notarizing."
  exit 1
fi

echo ">> Cleaning previous build…"
rm -rf build/release
mkdir -p artifacts

echo ">> Building Release…"
mkdir -p build/release
xcodebuild -project Citadel.xcodeproj -scheme CitadelFull -configuration Release \
  -derivedDataPath build/release \
  CODE_SIGN_IDENTITY="$SIGN_ID" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="$TEAM_ID" \
  OTHER_CODE_SIGN_FLAGS="--timestamp --options=runtime" build > build/release/xcodebuild.log 2>&1

if [ ! -d "$APP_BUNDLE" ]; then
    echo "ERROR: $APP_BUNDLE missing"
    tail -50 build/release/xcodebuild.log
    exit 1
fi

echo ">> Stripping duplicate helper from Resources/ if any…"
rm -f "$APP_BUNDLE/Contents/Resources/CitadelHelper"

echo ">> Re-signing helper without get-task-allow…"
HELPER="$APP_BUNDLE/Contents/MacOS/CitadelHelper"
codesign --remove-signature "$HELPER" || true
codesign --force --options=runtime --timestamp \
  --entitlements "$HELPER_ENT" \
  --sign "$SIGN_ID" \
  "$HELPER"

echo ">> Re-signing network system extension…"
NETEXT="$APP_BUNDLE/Contents/Library/SystemExtensions/CitadelNetExt.systemextension"
if [ -d "$NETEXT" ]; then
  codesign --remove-signature "$NETEXT" || true
  codesign --force --options=runtime --timestamp \
    --entitlements "$NETEXT_ENT" \
    --sign "$SIGN_ID" \
    "$NETEXT"
else
  echo "warning: system extension not found, skipping"
fi

echo ">> Re-signing app without get-task-allow…"
codesign --remove-signature "$APP_BUNDLE" || true
codesign --force --options=runtime --timestamp \
  --entitlements "$APP_ENT" \
  --sign "$SIGN_ID" \
  "$APP_BUNDLE"

echo ">> Verifying signatures…"
codesign --verify --strict --deep --verbose=2 "$APP_BUNDLE"

echo ">> Zipping for notarization…"
ZIP="artifacts/Citadel-${VERSION}-notary.zip"
rm -f "$ZIP"
/usr/bin/ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP"

echo ">> Submitting to Apple notary…"
xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait

echo ">> Stapling notary ticket…"
xcrun stapler staple "$APP_BUNDLE"
xcrun stapler validate "$APP_BUNDLE"

echo ">> Done. Notarized app at $APP_BUNDLE"
