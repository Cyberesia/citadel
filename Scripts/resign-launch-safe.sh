#!/usr/bin/env bash
# Re-sign an installed Citadel.app so it can launch without Developer ID provisioning
# profiles for System Extension / Network Extension on the host app.
#
# Full Fortress (embedded NetExt activation) still requires Developer ID provisioning
# profiles — see RELEASE.md. This script gets the GUI running again immediately.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-/Applications/Citadel.app}"
# shellcheck source=load-signing-env.sh
source "$ROOT/Scripts/load-signing-env.sh"
citadel_require_team_id
citadel_require_signing_files || exit 1

IDENTITY="${CODESIGN_IDENTITY:-$(security find-identity -v -p codesigning | grep "Developer ID Application:.*(${TEAM_ID})" | head -1 | awk '{print $2}')}"
APP_ENT="${APP_ENT:-$ROOT/Packaging/Entitlements/CitadelDirectLaunch.entitlements}"
HELPER_ENT="$ROOT/Packaging/Entitlements/CitadelHelper.entitlements"
NETEXT_ENT="$ROOT/Packaging/Entitlements/CitadelNetExt.entitlements"
BUILD_DYLIB="${BUILD_DYLIB:-$ROOT/.build/xcode-direct/Build/Products/Release/Citadel.app/Contents/Frameworks/libswiftCompatibilitySpan.dylib}"

[ -n "$IDENTITY" ] || { echo "error: no Developer ID identity for team $TEAM_ID" >&2; exit 1; }
[ -d "$APP" ] || { echo "error: app not found: $APP" >&2; exit 1; }

if [ -f "$BUILD_DYLIB" ]; then
  echo "Restoring Apple libswiftCompatibilitySpan.dylib…"
  cp "$BUILD_DYLIB" "$APP/Contents/Frameworks/libswiftCompatibilitySpan.dylib"
else
  echo "warning: $BUILD_DYLIB missing — skipping Apple dylib restore." >&2
fi

echo "Re-signing helper / NetExt / app (launch-safe host entitlements)…"
codesign --force --timestamp --options runtime --entitlements "$HELPER_ENT" --sign "$IDENTITY" "$APP/Contents/MacOS/CitadelHelper"
if [ -d "$APP/Contents/Library/SystemExtensions/CitadelNetExt.systemextension" ]; then
  codesign --force --timestamp --options runtime --entitlements "$NETEXT_ENT" --sign "$IDENTITY" \
    "$APP/Contents/Library/SystemExtensions/CitadelNetExt.systemextension"
fi
codesign --force --timestamp --options runtime --entitlements "$APP_ENT" --sign "$IDENTITY" "$APP"

echo "Verifying…"
codesign --verify --deep --strict --verbose=2 "$APP"
"$APP/Contents/MacOS/Citadel" &
PID=$!
sleep 2
if kill -0 "$PID" 2>/dev/null; then
  echo "Launch OK (pid $PID). Stopping test process…"
  kill "$PID" 2>/dev/null || true
else
  echo "warning: binary still exits immediately — check Console." >&2
  exit 1
fi

echo "Done. Open with: open \"$APP\""
