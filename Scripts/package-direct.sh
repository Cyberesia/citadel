#!/usr/bin/env bash
# Direct distribution package for Citadel — Release build → Developer ID sign
# (app + helper + NetExt) → DMG → optional notarize/staple.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=load-signing-env.sh
source "$ROOT_DIR/Scripts/load-signing-env.sh"
citadel_require_team_id
citadel_require_signing_files || exit 1

APP_NAME="${APP_NAME:-Citadel}"
VERSION="${VERSION:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
BUNDLE_ID="${BUNDLE_ID:-com.citadel.firewall}"
# Local keychain alias for notary credentials (see RELEASE.md). Not visible to Apple.
NOTARYTOOL_PROFILE="${NOTARYTOOL_PROFILE:-citadel-notary}"

XCODE_DERIVED="${XCODE_DERIVED:-$ROOT_DIR/.build/xcode-direct}"
BUILD_DIR="$XCODE_DERIVED/Build/Products/Release"
DIST_DIR="$ROOT_DIR/.build/distribution/direct"
APP_PATH="$DIST_DIR/$APP_NAME.app"
DMG_PATH="$DIST_DIR/$APP_NAME.dmg"

APP_ENT="$ROOT_DIR/Packaging/Entitlements/CitadelDirect.entitlements"
APP_ENT_LAUNCH="$ROOT_DIR/Packaging/Entitlements/CitadelDirectLaunch.entitlements"
HELPER_ENT="$ROOT_DIR/Packaging/Entitlements/CitadelHelper.entitlements"
NETEXT_ENT="$ROOT_DIR/Packaging/Entitlements/CitadelNetExt.entitlements"
APP_ENT_BUILD="$ROOT_DIR/Packaging/Entitlements/CitadelBuild.entitlements"
HELPER_ENT_BUILD="$ROOT_DIR/Packaging/Entitlements/CitadelHelperBuild.entitlements"
NETEXT_ENT_BUILD="$ROOT_DIR/Packaging/Entitlements/CitadelNetExtBuild.entitlements"

# Host app entitlements: System Extension / Network Extension require Developer ID
# provisioning profiles at runtime. Without them, AMFI kills the app on launch.
APP_SIGN_ENT="$APP_ENT_LAUNCH"
if [[ -n "${CITADEL_PROVISIONING_PROFILE:-}" && -f "${CITADEL_PROVISIONING_PROFILE}" ]]; then
  APP_SIGN_ENT="$APP_ENT"
  echo "Using full distribution entitlements with provisioning profile: $CITADEL_PROVISIONING_PROFILE"
elif [[ "${CITADEL_FULL_ENTITLEMENTS:-0}" == "1" ]]; then
  APP_SIGN_ENT="$APP_ENT"
  echo "warning: CITADEL_FULL_ENTITLEMENTS=1 without CITADEL_PROVISIONING_PROFILE — app may not launch." >&2
else
  echo "Using launch-safe host entitlements (no System Extension on app). See RELEASE.md for full Fortress profiles."
fi

# Resolve identity SHA-1 (avoids ambiguous duplicate cert names in keychain).
if [[ -z "${CODESIGN_IDENTITY:-}" ]]; then
  CODESIGN_IDENTITY="$(security find-identity -v -p codesigning \
    | grep "Developer ID Application:.*(${TEAM_ID})" \
    | head -1 | awk '{print $2}')"
fi
if [[ -z "${CODESIGN_IDENTITY:-}" ]]; then
  echo "error: no Developer ID Application identity for team ${TEAM_ID}." >&2
  echo "Set CODESIGN_IDENTITY=\"Developer ID Application: … (${TEAM_ID})\" or install the cert." >&2
  exit 1
fi
echo "Using signing identity: $CODESIGN_IDENTITY"

# Unmount branded DMGs before touching .build/distribution/direct (mounted volume or open
# Citadel.dmg in Finder/Cursor makes rm -rf on that folder fail with "Directory not empty").
detach_existing_dmg_volumes() {
  shopt -s nullglob
  local mount_path
  for mount_path in /Volumes/"$APP_NAME"*; do
    if [[ -d "$mount_path" ]]; then
      echo "Detaching existing DMG mount: $mount_path"
      hdiutil detach "$mount_path" -force 2>/dev/null || diskutil unmount force "$mount_path" 2>/dev/null || true
    fi
  done
  shopt -u nullglob
}

detach_hdiutil_volumes_named_like_app() {
  CITADEL_DMG_APP_NAME="$APP_NAME" /usr/bin/python3 <<'PY' 2>/dev/null || true
import os, plistlib, subprocess
name = os.environ.get("CITADEL_DMG_APP_NAME", "Citadel")
try:
    blob = subprocess.check_output(["hdiutil", "info", "-plist"], stderr=subprocess.DEVNULL)
except subprocess.CalledProcessError:
    raise SystemExit(0)
data = plistlib.loads(blob)
for image in data.get("images") or []:
    for ent in image.get("system-entities") or []:
        mp = ent.get("mount-point") or ""
        if not mp.startswith("/Volumes/"):
            continue
        base = mp[len("/Volumes/") :]
        if base != name and not base.startswith(name + " "):
            continue
        dev = ent.get("dev-entry")
        if dev:
            subprocess.call(
                ["hdiutil", "detach", dev, "-force"],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
PY
}

detach_all_dmg_mounts_for_packaging() {
  detach_hdiutil_volumes_named_like_app
  detach_existing_dmg_volumes
}

prepare_distribution_dir() {
  detach_all_dmg_mounts_for_packaging
  mkdir -p "$DIST_DIR"
  if [[ -e "$APP_PATH" ]]; then
    rm -rf "$APP_PATH" || {
      echo "error: could not remove $APP_PATH" >&2
      echo "       Quit Citadel if it is running from the distribution folder." >&2
      exit 1
    }
  fi
  if [[ -e "$DMG_PATH" ]]; then
    rm -f "$DMG_PATH" || {
      echo "error: could not remove $DMG_PATH (eject /Volumes/$APP_NAME and close the file)" >&2
      exit 1
    }
  fi
  shopt -s nullglob
  for _rw in "$DIST_DIR"/rw.*"${APP_NAME}.dmg"; do
    rm -f "$_rw" || true
  done
  shopt -u nullglob
}

echo "Preparing coworkcore (if present)…"
if [[ "${SKIP_COWORKCORE:-0}" != "1" && -x "$ROOT_DIR/Scripts/prepare-coworkcore.sh" ]]; then
  "$ROOT_DIR/Scripts/prepare-coworkcore.sh" || echo "warning: prepare-coworkcore failed (continuing)." >&2
fi

echo "Generating Xcode project…"
(
  cd "$ROOT_DIR"
  xcodegen generate
)

echo "Building $APP_NAME Release (CitadelFull = app + helper + NetExt)…"
(
  cd "$ROOT_DIR"
  set +e
  xcodebuild \
    -scheme CitadelFull \
    -configuration Release \
    -derivedDataPath "$XCODE_DERIVED" \
    -destination 'generic/platform=macOS' \
    -resolvePackageDependencies \
    -skipMacroValidation
  _resolve_status=$?
  set -e
  if [[ "$_resolve_status" -ne 0 ]]; then
    echo "warning: resolvePackageDependencies exited $_resolve_status (continuing)." >&2
  fi

  # Build unsigned with minimal entitlements (Murmure-style), then re-sign for distribution below.
  # Network Extension / System Extension entitlements require provisioning profiles during
  # xcodebuild Manual signing; applying Packaging/* entitlements at codesign time avoids that.
  xcodebuild \
    -scheme CitadelFull \
    -configuration Release \
    -derivedDataPath "$XCODE_DERIVED" \
    -destination 'generic/platform=macOS' \
    -skipMacroValidation \
    build \
    ARCHS=arm64 \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=YES \
    Citadel_CODE_SIGN_ENTITLEMENTS="$APP_ENT_BUILD" \
    CitadelHelper_CODE_SIGN_ENTITLEMENTS="$HELPER_ENT_BUILD" \
    CitadelNetExt_CODE_SIGN_ENTITLEMENTS="$NETEXT_ENT_BUILD" \
    SWIFT_ENABLE_EXPLICIT_MODULES=NO
)

BUILT_APP="$BUILD_DIR/$APP_NAME.app"
if [[ ! -d "$BUILT_APP" ]]; then
  echo "error: built app missing at $BUILT_APP" >&2
  exit 1
fi

# If NetExt embed script skipped, copy manually.
NETEXT_SRC="$BUILD_DIR/CitadelNetExt.systemextension"
NETEXT_DST="$BUILT_APP/Contents/Library/SystemExtensions/CitadelNetExt.systemextension"
if [[ -d "$NETEXT_SRC" && ! -d "$NETEXT_DST" ]]; then
  echo "Embedding CitadelNetExt into app bundle…"
  mkdir -p "$BUILT_APP/Contents/Library/SystemExtensions"
  rm -rf "$NETEXT_DST"
  cp -R "$NETEXT_SRC" "$NETEXT_DST"
fi

prepare_distribution_dir
ditto "$BUILT_APP" "$APP_PATH"

# Strip debug helper copies if any.
rm -f "$APP_PATH/Contents/Resources/CitadelHelper" || true
# Xcode embeds libswiftCompatibilitySpan unsigned (TeamIdentifier=not set) — notarization
# rejects it; macOS 14+ resolves the weak @rpath link without bundling it.
rm -f "$APP_PATH/Contents/Frameworks/libswiftCompatibilitySpan.dylib" || true

sign_path() {
  local path="$1"
  local ents="${2:-}"
  if [[ ! -e "$path" ]]; then
    return 0
  fi
  if [[ -n "$ents" ]]; then
    codesign --force --timestamp --options runtime \
      --entitlements "$ents" \
      --sign "$CODESIGN_IDENTITY" \
      "$path"
  else
    codesign --force --timestamp --options runtime \
      --sign "$CODESIGN_IDENTITY" \
      "$path"
  fi
}

# Xcode embeds Apple Swift/runtime shims (e.g. libswiftCompatibilitySpan.dylib).
# Re-signing them with Developer ID breaks AMFI at launch — leave Apple-signed shims alone.
should_sign_nested() {
  local path="$1"
  local info ident team
  info="$(codesign -dv --verbose=4 "$path" 2>&1 || true)"
  ident="$(printf '%s\n' "$info" | sed -n 's/^Identifier=//p' | head -1)"
  team="$(printf '%s\n' "$info" | sed -n 's/^TeamIdentifier=//p' | head -1)"
  if [[ "$ident" == com.apple.* ]]; then
    return 1
  fi
  if [[ "$team" == "not set" && "$info" == *"Apple"* ]]; then
    return 1
  fi
  return 0
}

echo "Signing nested code (inside-out)…"

# Frameworks / dylibs
shopt -s nullglob
for framework in "$APP_PATH/Contents/Frameworks/"*.framework; do
  should_sign_nested "$framework" && sign_path "$framework"
done
for dylib in "$APP_PATH/Contents/MacOS/"*.dylib "$APP_PATH/Contents/Frameworks/"*.dylib; do
  should_sign_nested "$dylib" && sign_path "$dylib"
done
# Bundled MLX / SPM bundles
for bundle in "$APP_PATH/Contents/Resources/"*.bundle; do
  sign_path "$bundle"
done
# coworkcore binaries
if [[ -d "$APP_PATH/Contents/Resources/coworkcore-bundled" ]]; then
  while IFS= read -r -d '' bin; do
    sign_path "$bin"
  done < <(find "$APP_PATH/Contents/Resources/coworkcore-bundled" -type f -perm -111 -print0 2>/dev/null)
fi
shopt -u nullglob

HELPER="$APP_PATH/Contents/MacOS/CitadelHelper"
if [[ -f "$HELPER" ]]; then
  echo "Signing helper…"
  codesign --remove-signature "$HELPER" 2>/dev/null || true
  sign_path "$HELPER" "$HELPER_ENT"
else
  echo "warning: CitadelHelper missing inside app — privileged helper will not work." >&2
fi

NETEXT="$APP_PATH/Contents/Library/SystemExtensions/CitadelNetExt.systemextension"
if [[ -d "$NETEXT" ]]; then
  echo "Signing network system extension…"
  codesign --remove-signature "$NETEXT" 2>/dev/null || true
  # Sign executable inside first if present
  if [[ -f "$NETEXT/Contents/MacOS/CitadelNetExt" ]]; then
    sign_path "$NETEXT/Contents/MacOS/CitadelNetExt" "$NETEXT_ENT"
  fi
  sign_path "$NETEXT" "$NETEXT_ENT"
else
  echo "warning: CitadelNetExt.systemextension missing — per-app filter will be unavailable." >&2
fi

echo "Signing app bundle…"
codesign --remove-signature "$APP_PATH" 2>/dev/null || true
# Stamp version into Info.plist if keys exist
if [[ -f "$APP_PATH/Contents/Info.plist" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP_PATH/Contents/Info.plist" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string $VERSION" "$APP_PATH/Contents/Info.plist" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP_PATH/Contents/Info.plist" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :CFBundleVersion string $BUILD_NUMBER" "$APP_PATH/Contents/Info.plist" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$APP_PATH/Contents/Info.plist" 2>/dev/null || true
fi
sign_path "$APP_PATH" "$APP_SIGN_ENT"

echo "Verifying signatures…"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

# --- DMG (detach / create-dmg / hdiutil fallback) ---

detach_all_dmg_mounts_for_packaging

DMG_STAGE="$(mktemp -d "/tmp/citadel-dmg-stage.XXXXXX")"
cleanup_dmg_stage() {
  rm -rf "$DMG_STAGE"
}
trap cleanup_dmg_stage EXIT
ditto "$APP_PATH" "$DMG_STAGE/$APP_NAME.app"

CREATE_DMG="$ROOT_DIR/Scripts/vendor/create-dmg/create-dmg"
BG_PNG="$ROOT_DIR/Packaging/DMG/dmg-background.png"
WATERMARK="${DMG_WATERMARK:-$ROOT_DIR/Resources/Assets.xcassets/AppIcon.appiconset/icon_512x512.png}"
ICNS_CANDIDATE="$ROOT_DIR/Packaging/Citadel.icns"
USE_SIMPLE_DMG=0
if [[ "${CITADEL_SIMPLE_DMG:-0}" == "1" ]]; then USE_SIMPLE_DMG=1; fi
if [[ ! -x "$CREATE_DMG" ]]; then
  echo "note: vendored create-dmg missing — using plain hdiutil DMG." >&2
  USE_SIMPLE_DMG=1
fi

DMG_VOLUME_NAME="${DMG_VOLUME_NAME:-Citadel}"

# Optional .icns for volume icon
if [[ ! -f "$ICNS_CANDIDATE" && -f "$WATERMARK" ]]; then
  ICONSET="$(mktemp -d "/tmp/citadel-iconset.XXXXXX")"
  mkdir -p "$ICONSET/Citadel.iconset"
  for sz in 16 32 128 256 512; do
    sips -z "$sz" "$sz" "$WATERMARK" --out "$ICONSET/Citadel.iconset/icon_${sz}x${sz}.png" >/dev/null
    sips -z $((sz * 2)) $((sz * 2)) "$WATERMARK" --out "$ICONSET/Citadel.iconset/icon_${sz}x${sz}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET/Citadel.iconset" -o "$ICNS_CANDIDATE" 2>/dev/null || true
  rm -rf "$ICONSET"
fi

if [[ "$USE_SIMPLE_DMG" == "0" ]]; then
  mkdir -p "$(dirname "$BG_PNG")"
  if [[ -f "$WATERMARK" ]] && swift "$ROOT_DIR/Scripts/render-dmg-background.swift" "$WATERMARK" "$BG_PNG"; then
    CDMG_ARGS=(
      --volname "$DMG_VOLUME_NAME"
      --window-pos 200 120
      --window-size 660 400
      --icon-size 100
      --text-size 12
      --icon "$APP_NAME.app" 180 190
      --hide-extension "$APP_NAME.app"
      --app-drop-link 480 190
      --background "$BG_PNG"
      --format UDZO
    )
    if [[ -f "$ICNS_CANDIDATE" ]]; then
      CDMG_ARGS+=(--volicon "$ICNS_CANDIDATE")
    fi
    CDMG_ARGS+=(--codesign "$CODESIGN_IDENTITY")
    detach_all_dmg_mounts_for_packaging
    if ! "$CREATE_DMG" "${CDMG_ARGS[@]}" "$DMG_PATH" "$DMG_STAGE"; then
      echo "warning: create-dmg failed — falling back to plain DMG." >&2
      rm -f "$DMG_PATH"
      detach_all_dmg_mounts_for_packaging
      USE_SIMPLE_DMG=1
    else
      echo "Created branded DMG."
    fi
  else
    echo "warning: could not render DMG background — plain DMG." >&2
    USE_SIMPLE_DMG=1
  fi
fi

if [[ "$USE_SIMPLE_DMG" == "1" ]]; then
  rm -f "$DMG_PATH"
  detach_all_dmg_mounts_for_packaging
  ln -sf /Applications "$DMG_STAGE/Applications"
  hdiutil create -volname "$DMG_VOLUME_NAME" -srcfolder "$DMG_STAGE" -ov -format UDZO "$DMG_PATH"
fi

if [[ "${SKIP_NOTARIZATION:-0}" == "1" ]]; then
  echo "note: SKIP_NOTARIZATION=1 — signed DMG only (not for distribution)."
elif [[ -n "${NOTARYTOOL_PROFILE:-}" ]]; then
  echo "Submitting DMG for notarization with profile: $NOTARYTOOL_PROFILE"
  xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARYTOOL_PROFILE" --wait
  xcrun stapler staple "$APP_PATH"
  xcrun stapler staple "$DMG_PATH"
  xcrun stapler validate "$DMG_PATH"
else
  echo "error: notary profile \"$NOTARYTOOL_PROFILE\" not found in Keychain." >&2
  echo "Create it once (same Apple ID / team as Murmure is fine):" >&2
  echo "  xcrun notarytool store-credentials $NOTARYTOOL_PROFILE \\" >&2
  echo "    --apple-id \"you@example.com\" --team-id $TEAM_ID --password \"<app-specific-password>\"" >&2
  echo "Or set SKIP_NOTARIZATION=1 for a local signed build only." >&2
  exit 1
fi

echo ""
echo "Direct package ready:"
echo "  $APP_PATH"
echo "  $DMG_PATH"
echo ""
echo "Verify:"
echo "  codesign --verify --deep --strict --verbose=2 \"$APP_PATH\""
echo "  spctl --assess --type execute --verbose=4 \"$APP_PATH\""
