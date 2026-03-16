#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT_DIR"
PUBSPEC_PATH="$ROOT_DIR/pubspec.yaml"
DIST_DIR="$ROOT_DIR/dist"
APP_NAME="${APP_NAME:-XWorkmate}"
BUILD_MODE="${BUILD_MODE:-release}"
PRODUCTS_DIR_NAME="$(tr '[:lower:]' '[:upper:]' <<< "${BUILD_MODE:0:1}")${BUILD_MODE:1}"

if [[ ! -f "$PUBSPEC_PATH" ]]; then
  echo "Missing pubspec: $PUBSPEC_PATH" >&2
  exit 1
fi

VERSION_LINE="$(sed -n 's/^version:[[:space:]]*//p' "$PUBSPEC_PATH" | head -n 1)"
if [[ -z "$VERSION_LINE" ]]; then
  echo "Unable to read version from $PUBSPEC_PATH" >&2
  exit 1
fi

APP_VERSION="${VERSION_LINE%%+*}"
APP_BUILD="${VERSION_LINE#*+}"
if [[ "$APP_BUILD" == "$VERSION_LINE" ]]; then
  APP_BUILD="1"
fi

BUILD_APP_PATH="$APP_DIR/build/macos/Build/Products/$PRODUCTS_DIR_NAME/$APP_NAME.app"
DIST_APP_PATH="$DIST_DIR/$APP_NAME.app"
DIST_DMG_PATH="$DIST_DIR/$APP_NAME-$APP_VERSION.dmg"

mkdir -p "$DIST_DIR"

echo "Building $APP_NAME $APP_VERSION ($APP_BUILD) for macOS..."
BUILD_ARGS=(
  flutter build macos
  "--$BUILD_MODE"
  --build-name="$APP_VERSION"
  --build-number="$APP_BUILD"
  --dart-define="XWORKMATE_DISPLAY_VERSION=$APP_VERSION"
  --dart-define="XWORKMATE_BUILD_NUMBER=$APP_BUILD"
)

if [[ -f "$APP_DIR/.dart_tool/package_config.json" ]]; then
  BUILD_ARGS+=(--no-pub)
fi

(
  cd "$APP_DIR"
  "${BUILD_ARGS[@]}"
)

if [[ ! -d "$BUILD_APP_PATH" ]]; then
  echo "Expected app bundle not found: $BUILD_APP_PATH" >&2
  exit 1
fi

rm -rf "$DIST_APP_PATH" "$DIST_DMG_PATH"
ditto "$BUILD_APP_PATH" "$DIST_APP_PATH"

echo "Packaging DMG..."
DMG_VOLUME_NAME="$APP_NAME" "$ROOT_DIR/scripts/create-dmg.sh" "$DIST_APP_PATH" "$DIST_DMG_PATH"

echo "App bundle: $DIST_APP_PATH"
echo "DMG: $DIST_DMG_PATH"
