#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DEFAULT_BRIDGE_DIR=""
for candidate in   "$ROOT_DIR/../xworkmate-bridge"   "$ROOT_DIR/../../xworkmate-bridge"
do
  if [[ -f "$candidate/go.mod" ]]; then
    DEFAULT_BRIDGE_DIR="$candidate"
    break
  fi
done
BRIDGE_DIR="${XWORKMATE_BRIDGE_DIR:-$DEFAULT_BRIDGE_DIR}"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR/build/bin}"
OUTPUT_PATH_BASE="${OUTPUT_DIR}/xworkmate-go-core"

if [[ "$(uname -s)" == *MINGW* || "$(uname -s)" == *MSYS* || "$(uname -s)" == *CYGWIN* ]]; then
  OUTPUT_PATH="${OUTPUT_PATH:-${OUTPUT_PATH_BASE}.exe}"
else
  OUTPUT_PATH="${OUTPUT_PATH:-${OUTPUT_PATH_BASE}}"
fi

if [[ ! -f "$BRIDGE_DIR/go.mod" ]]; then
  echo "Missing xworkmate-bridge repo or go.mod in $BRIDGE_DIR" >&2
  exit 1
fi

if ! command -v go >/dev/null 2>&1; then
  echo "Go toolchain is required to build xworkmate-go-core" >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"

echo "Building xworkmate-go-core from xworkmate-bridge..."
(
  cd "$BRIDGE_DIR"
  GO111MODULE=on go build -o "$OUTPUT_PATH" .
)

chmod +x "$OUTPUT_PATH"
echo "Built: $OUTPUT_PATH"
