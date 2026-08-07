#!/usr/bin/env bash
# Prepare CoworkCore binary + managed resources for Citadel.app bundle.
# Upstream: https://github.com/iOfficeAI/AionCore (Apache-2.0) — see ATTRIBUTIONS.md
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

log() { echo "$@" >&2; }

PLATFORM="darwin"
ARCH="$(uname -m)"
case "$ARCH" in
  arm64) RUNTIME_KEY="darwin-arm64"; RUST_TRIPLE="aarch64-apple-darwin" ;;
  x86_64) RUNTIME_KEY="darwin-x64"; RUST_TRIPLE="x86_64-apple-darwin" ;;
  *) log "Unsupported architecture: $ARCH"; exit 1 ;;
esac

OUT_DIR="$ROOT/Resources/coworkcore-bundled/$RUNTIME_KEY"
STAGING="$ROOT/build/coworkcore-staging"
CACHE_BIN="$ROOT/build/coworkcore-cache/aioncore"
REPO_DIR="$ROOT/build/AionCore"
BINARY_NAME="aioncore"
COWORK_BINARY_NAME="coworkcore"
UPSTREAM=""

mkdir -p "$STAGING" "$(dirname "$CACHE_BIN")"

resolve_upstream_binary() {
  if [[ -n "${COWORKCORE_LOCAL_BINARY:-}" && -x "${COWORKCORE_LOCAL_BINARY}" ]]; then
    UPSTREAM="$COWORKCORE_LOCAL_BINARY"
    return 0
  fi
  if [[ -x "$HOME/.cargo/bin/aioncore" ]]; then
    UPSTREAM="$HOME/.cargo/bin/aioncore"
    return 0
  fi
  if [[ -x "$CACHE_BIN" ]]; then
    UPSTREAM="$CACHE_BIN"
    return 0
  fi
  return 1
}

download_release_binary() {
  local tag asset url archive extracted
  log "→ Resolving latest AionCore release…"
  tag="$(curl -fsSL "https://api.github.com/repos/iOfficeAI/AionCore/releases/latest" \
    | python3 -c "import sys,json; print(json.load(sys.stdin)['tag_name'])")"
  asset="aioncore-${tag}-${RUST_TRIPLE}.tar.gz"
  url="https://github.com/iOfficeAI/AionCore/releases/download/${tag}/${asset}"
  archive="$STAGING/$asset"

  log "→ Downloading $asset"
  curl -fL --retry 3 --retry-delay 2 -o "$archive" "$url"

  rm -rf "$STAGING/extract"
  mkdir -p "$STAGING/extract"
  tar -xzf "$archive" -C "$STAGING/extract"
  extracted="$(find "$STAGING/extract" -type f -name "$BINARY_NAME" | head -1)"
  if [[ -z "$extracted" || ! -f "$extracted" ]]; then
    log "   Could not find executable in archive"
    return 1
  fi
  cp -f "$extracted" "$CACHE_BIN"
  chmod +x "$CACHE_BIN"
  UPSTREAM="$CACHE_BIN"
}

build_from_source() {
  log "→ Building AionCore from source (this may take several minutes)…"
  if [[ ! -d "$REPO_DIR/.git" ]]; then
    git clone --depth 1 https://github.com/iOfficeAI/AionCore.git "$REPO_DIR"
  else
    git -C "$REPO_DIR" pull --ff-only
  fi
  cargo build --release --locked --manifest-path "$REPO_DIR/crates/aionui-app/Cargo.toml"
  cp -f "$REPO_DIR/target/release/$BINARY_NAME" "$CACHE_BIN"
  chmod +x "$CACHE_BIN"
  UPSTREAM="$CACHE_BIN"
}

prepare_managed_resources() {
  local bundle_out="$STAGING/managed-resources"
  local data_dir="$STAGING/prepare-data"

  rm -rf "$bundle_out" "$data_dir"
  mkdir -p "$bundle_out" "$data_dir"

  log "→ Preparing managed resources…"
  AIONUI_BUNDLED_MANAGED_RESOURCES="" "$UPSTREAM" \
    --data-dir "$data_dir" \
    prepare-managed-resources \
    --bundle-out "$bundle_out"
  rm -rf "$data_dir"
}

if resolve_upstream_binary; then
  log "→ Using existing binary: $UPSTREAM"
elif download_release_binary; then
  :
elif build_from_source; then
  :
else
  log "Failed to obtain AionCore binary"
  exit 1
fi

prepare_managed_resources

log "→ Installing bundle to $OUT_DIR"
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"
cp -f "$UPSTREAM" "$OUT_DIR/$COWORK_BINARY_NAME"
chmod +x "$OUT_DIR/$COWORK_BINARY_NAME"
cp -R "$STAGING/managed-resources" "$OUT_DIR/managed-resources"

python3 - "$OUT_DIR/manifest.json" "$RUNTIME_KEY" "$UPSTREAM" <<'PY'
import json, subprocess, sys
out, runtime, upstream = sys.argv[1:4]
try:
    tag = subprocess.check_output([upstream, "--version"], text=True, stderr=subprocess.STDOUT).strip()
except Exception:
    tag = "unknown"
payload = {
    "runtimeKey": runtime,
    "binaryName": "coworkcore",
    "upstreamBinary": "aioncore",
    "upstreamVersion": tag,
    "source": "AionCore",
}
with open(out, "w", encoding="utf-8") as f:
    json.dump(payload, f, indent=2)
    f.write("\n")
PY

log ""
log "CoworkCore ready:"
log "  $OUT_DIR/$COWORK_BINARY_NAME"
ls -lh "$OUT_DIR/$COWORK_BINARY_NAME" >&2
