#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

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
