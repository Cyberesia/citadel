#!/usr/bin/env bash
# Source from packaging scripts. Loads Scripts/signing.local.env (gitignored).
# shellcheck disable=SC1091

CITADEL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

ENV_FILE="${CITADEL_SIGNING_ENV:-$CITADEL_ROOT/Scripts/signing.local.env}"
if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "$ENV_FILE"
  set +a
fi

citadel_require_team_id() {
  if [[ -z "${TEAM_ID:-}" || "$TEAM_ID" == "YOUR_TEAM_ID" ]]; then
    cat >&2 <<EOF
error: TEAM_ID is not set.

  cp Scripts/signing.local.env.example Scripts/signing.local.env
  # edit TEAM_ID, then:
  ./Scripts/prepare-signing.sh

Or export TEAM_ID before running this script.
EOF
    return 1
  fi
}

citadel_require_signing_files() {
  local missing=0
  for f in \
    "$CITADEL_ROOT/Sources/Helper/Info.plist" \
    "$CITADEL_ROOT/Packaging/Entitlements/CitadelHelper.entitlements"
  do
    if [[ ! -f "$f" ]]; then
      echo "error: missing $f — run ./Scripts/prepare-signing.sh" >&2
      missing=1
    fi
  done
  return "$missing"
}
