#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OS_VERSION="${1:-1.09}"
ARCHIVE_URL="https://codeload.github.com/OpCoders-Inc/c64os-dev/tar.gz/refs/heads/main"
ARCHIVE_ROOT="c64os-dev-main"
TMP_DIR="$(mktemp -d)"
UPSTREAM_OS_DIR="$TMP_DIR/$ARCHIVE_ROOT/include/v${OS_VERSION}/os"
LOCAL_OS_DIR="$ROOT_DIR/os"
OVERRIDE_MODULES="$ROOT_DIR/overrides/c64os/v${OS_VERSION}/os/h/modules.h"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

if [[ ! -f "$OVERRIDE_MODULES" ]]; then
  echo "Missing local override file: $OVERRIDE_MODULES" >&2
  exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "curl is required to fetch C64 OS include files." >&2
  exit 1
fi

echo "Fetching C64 OS include/v${OS_VERSION}/os from upstream..."
if ! curl -fsSL "$ARCHIVE_URL" -o "$TMP_DIR/c64os-dev.tar.gz"; then
  echo "Failed to download upstream archive. Check network connectivity." >&2
  exit 1
fi

tar -xzf "$TMP_DIR/c64os-dev.tar.gz" -C "$TMP_DIR"

if [[ ! -d "$UPSTREAM_OS_DIR" ]]; then
  echo "Upstream path not found in archive: include/v${OS_VERSION}/os" >&2
  exit 1
fi

rsync -a --delete "$UPSTREAM_OS_DIR/" "$LOCAL_OS_DIR/"
cp "$OVERRIDE_MODULES" "$LOCAL_OS_DIR/h/modules.h"

echo "Synced os/ from include/v${OS_VERSION}/os"
echo "Re-applied local override: os/h/modules.h"
