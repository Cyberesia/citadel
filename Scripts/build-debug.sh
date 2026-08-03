#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ ! -f Sources/Helper/Info.plist ]]; then
  if [[ -f Scripts/signing.local.env ]]; then
    ./Scripts/prepare-signing.sh
  else
    cat >&2 <<'EOF'
error: Sources/Helper/Info.plist is missing (gitignored — not in the public repo).

  cp Scripts/signing.local.env.example Scripts/signing.local.env
  # edit TEAM_ID (any value works for unsigned debug builds)
  ./Scripts/prepare-signing.sh

EOF
    exit 1
  fi
fi

APP="build/Build/Products/Debug/Citadel.app"

if [ "${SKIP_COWORKCORE:-0}" != "1" ]; then
  ./Scripts/prepare-coworkcore.sh
fi

xcodegen generate
xcodebuild \
  -scheme Citadel \
  -configuration Debug \
  -derivedDataPath build \
  -skipMacroValidation \
  build

echo ""
echo "Built: $(pwd)/$APP"

# Launch unless NO_RUN=1 was passed. CITADEL_DEMO=1 loads demo data.
if [ "${NO_RUN:-0}" != "1" ]; then
  echo "Relaunching…"
  killall Citadel 2>/dev/null || true
  sleep 1
  open "$APP"
else
  echo "Run UI demo:   CITADEL_DEMO=1 open $APP"
  echo "Run real mode: open $APP"
fi
