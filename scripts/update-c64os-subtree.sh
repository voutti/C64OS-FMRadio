#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OS_VERSION="${1:-1.09}"

cd "$ROOT_DIR"

"$ROOT_DIR/scripts/sync-c64os-os.sh" "$OS_VERSION"

echo "Updated local os/ from upstream include/v${OS_VERSION}/os"
