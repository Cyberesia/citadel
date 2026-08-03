#!/usr/bin/env bash
# Materialize gitignored signing files from .example templates.
# Skips files that already exist (safe to re-run).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=load-signing-env.sh
source "$ROOT/Scripts/load-signing-env.sh"

citadel_require_team_id

materialize() {
  local example="$1" dest="$2"
  if [[ -f "$dest" ]]; then
    echo "keep: $dest (already exists)"
    return 0
  fi
  if [[ ! -f "$example" ]]; then
    echo "error: missing template $example" >&2
    exit 1
  fi
  sed "s/YOUR_TEAM_ID/${TEAM_ID}/g" "$example" > "$dest"
  echo "created: $dest"
}

materialize "$ROOT/Sources/Helper/Info.plist.example" "$ROOT/Sources/Helper/Info.plist"
materialize \
  "$ROOT/Packaging/Entitlements/CitadelHelper.entitlements.example" \
  "$ROOT/Packaging/Entitlements/CitadelHelper.entitlements"

echo ""
echo "Signing files ready. Run ./Scripts/package-direct.sh to build a signed DMG."
