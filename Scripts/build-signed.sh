#!/usr/bin/env bash
# Build Citadel, re-sign the app + embedded helper with the Cyberesia Developer ID,
# install to /Applications, and launch. This is what makes the privileged helper
# (SMAppService daemon) registerable — ad-hoc signed builds cannot register it.
#
# Local testing only. Distribution to other machines additionally needs notarization
# (and a .pkg or stapled .app), which this script does NOT do.
set -euo pipefail
cd "$(dirname "$0")/.."

TEAM_ID="98Y85F8KFJ"
# Resolve a single identity SHA-1 (the keychain can hold duplicate certs with the
# same name, which makes codesign fail with "ambiguous"); pick the first match.
IDENTITY="$(security find-identity -v -p codesigning \
  | grep "Developer ID Application: Cyberesia SA (${TEAM_ID})" \
  | head -1 | awk '{print $2}')"
[ -n "$IDENTITY" ] || { echo "error: no Developer ID identity for team ${TEAM_ID}"; exit 1; }
echo "==> Using signing identity $IDENTITY"
CONFIG="Debug"
APP="build/Build/Products/${CONFIG}/Citadel.app"
HELPER_EMBED="$APP/Contents/MacOS/CitadelHelper"
APP_ENT="Sources/GUI/Citadel.debug.entitlements"   # minimal: sandbox off + network (helper test)
HELPER_ENT="Sources/Helper/Helper.entitlements"
INSTALL_DIR="/Applications"
INSTALLED_APP="$INSTALL_DIR/Citadel.app"

echo "==> Generating project"
xcodegen generate

echo "==> Building ($CONFIG)"
xcodebuild \
  -scheme Citadel \
  -configuration "$CONFIG" \
  -derivedDataPath build \
  build

[ -d "$APP" ] || { echo "error: app not found at $APP"; exit 1; }
[ -f "$HELPER_EMBED" ] || { echo "error: embedded helper not found at $HELPER_EMBED"; exit 1; }

# Sign inside-out: nested dylibs, then the embedded helper, then the app bundle.
echo "==> Signing nested dylibs"
for dylib in "$APP/Contents/MacOS/"*.dylib; do
  [ -e "$dylib" ] || continue
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$dylib"
done

echo "==> Signing embedded helper"
codesign --force --options runtime --timestamp \
  --sign "$IDENTITY" \
  --entitlements "$HELPER_ENT" \
  "$HELPER_EMBED"

echo "==> Signing app bundle"
codesign --force --options runtime --timestamp \
  --sign "$IDENTITY" \
  --entitlements "$APP_ENT" \
  "$APP"

echo "==> Verifying signatures"
codesign --verify --deep --strict --verbose=2 "$APP"
codesign -dv --verbose=4 "$HELPER_EMBED" 2>&1 | grep -E "Authority|TeamIdentifier|Identifier" || true

echo "==> Installing to $INSTALL_DIR"
# Remove the old copy so SMAppService re-reads the freshly signed bundle.
killall Citadel 2>/dev/null || true
rm -rf "$INSTALLED_APP"
cp -R "$APP" "$INSTALLED_APP"

echo "==> Launching"
open "$INSTALLED_APP"

cat <<EOF

Done. Next manual step (one time):
  System Settings → General → Login Items & Extensions → Allow "Citadel"
  (the daemon "com.citadel.firewall.helper" must be enabled)

Then the Rules/Monitor panels will show live helper data. To watch the daemon:
  log stream --predicate 'process == "CitadelHelper"' --info
EOF
