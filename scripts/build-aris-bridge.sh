#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BRIDGE_DIR="$ROOT_DIR/go/aris_bridge"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR/build/bin}"
OUTPUT_PATH="${OUTPUT_PATH:-$OUTPUT_DIR/xworkmate-aris-bridge}"

if [[ ! -f "$BRIDGE_DIR/go.mod" ]]; then
  echo "Missing go.mod in $BRIDGE_DIR" >&2
  exit 1
fi

if ! command -v go >/dev/null 2>&1; then
  echo "Go toolchain is required to build xworkmate-aris-bridge" >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"

echo "Building xworkmate-aris-bridge..."
(
  cd "$BRIDGE_DIR"
  GO111MODULE=on go build -o "$OUTPUT_PATH" .
)

chmod +x "$OUTPUT_PATH"
echo "Built: $OUTPUT_PATH"
