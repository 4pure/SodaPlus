#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/bridge"

FEATURE_ARGS=()
if [[ -f "$ROOT/Vendor/libresoda/Cargo.toml" ]]; then
  FEATURE_ARGS=(--features libresoda)
  echo "libresoda detected — building with --features libresoda"
else
  echo "Vendor/libresoda missing — building stub bridge (search/download will error until fetch)."
fi

echo
echo "======== [1/1] cargo build -p sodaplus-bridge --release ========"
echo
if [[ ${#FEATURE_ARGS[@]} -gt 0 ]]; then
  cargo build --release "${FEATURE_ARGS[@]}"
else
  cargo build --release
fi
echo "OK: $ROOT/bridge/target/release/sodaplus-bridge"
