#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT_DIR"
PUBSPEC_PATH="$ROOT_DIR/pubspec.yaml"
DIST_DIR="$ROOT_DIR/dist"
APP_NAME="${APP_NAME:-XWorkmate}"
BUILD_MODE="${BUILD_MODE:-release}"
APP_STORE_DEFINE="${APP_STORE_DEFINE:---dart-define=XWORKMATE_APP_STORE=${XWORKMATE_APP_STORE:-true}}"
SIGN_IDENTITY="${XWORKMATE_SIGN_IDENTITY:-}"
PRODUCTS_DIR_NAME="$(tr '[:lower:]' '[:upper:]' <<< "${BUILD_MODE:0:1}")${BUILD_MODE:1}"
FLUTTER_BUILD_STATE_DIR="${ROOT_DIR}/.dart_tool/flutter_build"
MACOS_BUILD_DIR="${ROOT_DIR}/build/macos"
NATIVE_ASSETS_DIR="${ROOT_DIR}/build/native_assets"
source "$ROOT_DIR/scripts/ci/apple_signing.sh"
APPLE_SIGNING_CLEANUP_COMMANDS=()
trap apple_run_cleanup EXIT

remove_tree_with_retries() {
  local path="$1"
  local attempts="${2:-5}"
  local delay_seconds="${3:-1}"
  local try=1

  [[ -e "$path" ]] || return 0

  while (( try <= attempts )); do
    chmod -R u+w "$path" 2>/dev/null || true
    rm -rf "$path" 2>/dev/null || true

    if [[ ! -e "$path" ]]; then
      return 0
    fi

    if (( try == attempts )); then
      echo "Failed to remove generated path after ${attempts} attempts: $path" >&2
      return 1
    fi

    sleep "$delay_seconds"
    ((try++))
  done
}

if [[ ! -f "$PUBSPEC_PATH" ]]; then
  echo "Missing pubspec: $PUBSPEC_PATH" >&2
  exit 1
fi

eval "$(python3 "$ROOT_DIR/scripts/ci/build_version.py" --format shell)"
BUILD_DATE_LINE="$(sed -n 's/^build-date:[[:space:]]*//p' "$PUBSPEC_PATH" | head -n 1)"
BUILD_ID_LINE="$(sed -n 's/^build-id:[[:space:]]*//p' "$PUBSPEC_PATH" | head -n 1)"

APP_VERSION="$DISPLAY_VERSION"
APP_RELEASE_VERSION="$PLATFORM_RELEASE_VERSION"
APP_BUILD="$BUILD_NUMBER"
APP_BUILD_DATE="${BUILD_DATE_LINE:-unknown}"
APP_BUILD_COMMIT="${BUILD_ID_LINE:-unknown}"

BUILD_APP_PATH="$APP_DIR/build/macos/Build/Products/$PRODUCTS_DIR_NAME/$APP_NAME.app"
DIST_APP_PATH="$DIST_DIR/$APP_NAME.app"
DIST_DMG_PATH="$DIST_DIR/$APP_NAME-$APP_VERSION.dmg"
mkdir -p "$DIST_DIR"

echo "Building $APP_NAME $APP_VERSION ($APP_BUILD) for macOS..."
# Flutter caches native-asset installation state under .dart_tool/flutter_build,
# but Xcode consumes the copied frameworks from build/native_assets/macos.
# Reset both locations so packaging cannot reuse a stale stamp or stale layout.
remove_tree_with_retries "$FLUTTER_BUILD_STATE_DIR"
remove_tree_with_retries "$MACOS_BUILD_DIR"
remove_tree_with_retries "$NATIVE_ASSETS_DIR"

if [[ -n "${APPLE_CERT_P12_BASE64:-}" &&
      -n "${APPLE_CERT_PASSWORD:-}" &&
      -n "${APPLE_KEYCHAIN_PASSWORD:-}" ]]; then
  echo "Provisioning Apple signing certificate for macOS build..."
  apple_setup_signing_keychain
else
  echo "Apple signing secrets not set; using existing local macOS signing context."
fi

BUILD_ARGS=(
  flutter build macos
  "--$BUILD_MODE"
  --build-name="$APP_RELEASE_VERSION"
  --build-number="$APP_BUILD"
  --dart-define="XWORKMATE_DISPLAY_VERSION=$APP_VERSION"
  --dart-define="XWORKMATE_BUILD_NUMBER=$APP_BUILD"
  --dart-define="XWORKMATE_BUILD_DATE=$APP_BUILD_DATE"
  --dart-define="XWORKMATE_BUILD_COMMIT=$APP_BUILD_COMMIT"
  "$APP_STORE_DEFINE"
)

(
  cd "$APP_DIR"
  "${BUILD_ARGS[@]}"
)

if [[ ! -d "$BUILD_APP_PATH" ]]; then
  echo "Expected app bundle not found: $BUILD_APP_PATH" >&2
  exit 1
fi

verify_bundle_signature() {
  local app_path="$1"
  echo "Verifying code signature: $app_path"
  codesign --verify --deep --verbose=2 "$app_path"
}

validate_bundle_dependencies() {
  local app_path="$1"
  bash "$ROOT_DIR/scripts/validate-macos-app-bundle.sh" "$app_path"
}

echo "Validating export compliance metadata..."
bash "$ROOT_DIR/scripts/check-apple-export-compliance.sh" "$BUILD_APP_PATH"
validate_bundle_dependencies "$BUILD_APP_PATH"

rm -rf "$DIST_APP_PATH" "$DIST_DMG_PATH"
ditto "$BUILD_APP_PATH" "$DIST_APP_PATH"
if [[ -n "$SIGN_IDENTITY" ]]; then
  echo "Re-signing app bundle with explicit identity..."
  codesign --force --deep --sign "$SIGN_IDENTITY" \
    --preserve-metadata=entitlements,requirements,flags,runtime \
    --timestamp=none "$DIST_APP_PATH"
else
  echo "Preserving Flutter build output signature."
fi

verify_bundle_signature "$DIST_APP_PATH"
validate_bundle_dependencies "$DIST_APP_PATH"

echo "Packaging DMG..."
DMG_VOLUME_NAME="$APP_NAME" "$ROOT_DIR/scripts/create-dmg.sh" "$DIST_APP_PATH" "$DIST_DMG_PATH"

echo "App bundle: $DIST_APP_PATH"
echo "DMG: $DIST_DMG_PATH"
