#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/Vendor/libresoda"

mkdir -p "$ROOT/Vendor"
if [[ -d "$DEST/.git" ]]; then
  echo "======== [1/1] update Vendor/libresoda ========"
  git -C "$DEST" pull --ff-only
  exit 0
fi

echo
echo "======== [1/1] clone sodahub-org/libresoda ========"
echo
rm -rf "$DEST"
git clone --depth 1 https://github.com/sodahub-org/libresoda.git "$DEST"
echo "OK: $DEST"
