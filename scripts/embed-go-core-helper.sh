#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_BUNDLE_PATH="${1:-${APP_BUNDLE_PATH:-}}"
BRIDGE_BINARY_NAME="${BRIDGE_BINARY_NAME:-xworkmate-go-core}"
BRIDGE_BUILD_PATH="${ROOT_DIR}/build/bin/${BRIDGE_BINARY_NAME}"

if [[ -z "$APP_BUNDLE_PATH" ]]; then
  echo "Missing app bundle path for embedded go-core helper" >&2
  exit 1
fi

if [[ ! -d "$APP_BUNDLE_PATH" ]]; then
  echo "App bundle does not exist: $APP_BUNDLE_PATH" >&2
  exit 1
fi

HELPERS_DIR="$APP_BUNDLE_PATH/Contents/Helpers"
HELPER_PATH="$HELPERS_DIR/$BRIDGE_BINARY_NAME"

bash "$ROOT_DIR/scripts/build-go-core.sh"

mkdir -p "$HELPERS_DIR"
ditto "$BRIDGE_BUILD_PATH" "$HELPER_PATH"
chmod +x "$HELPER_PATH"

SIGN_IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY:-${CODE_SIGN_IDENTITY:--}}"
if [[ -n "$SIGN_IDENTITY" && "$SIGN_IDENTITY" != "-" ]]; then
  codesign --force --sign "$SIGN_IDENTITY" --timestamp=none "$HELPER_PATH"
else
  echo "Skipping helper codesign: no explicit signing identity provided."
fi

echo "Embedded go-core helper: $HELPER_PATH"
