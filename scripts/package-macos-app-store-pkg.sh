#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist/macos-app-store"
APP_NAME="${APP_NAME:-XWorkmate}"
APP_STORE_DEFINE="${APP_STORE_DEFINE:---dart-define=XWORKMATE_APP_STORE=${XWORKMATE_APP_STORE:-true}}"
source "$ROOT_DIR/scripts/ci/apple_signing.sh"
APPLE_SIGNING_CLEANUP_COMMANDS=()
trap apple_run_cleanup EXIT

required_vars=(
  APPLE_CERT_P12_BASE64
  APPLE_CERT_PASSWORD
  APPLE_MAC_PROVISION_PROFILE_BASE64
  APPLE_KEYCHAIN_PASSWORD
)

missing=()
for var_name in "${required_vars[@]}"; do
  if [[ -z "${!var_name:-}" ]]; then
    missing+=("$var_name")
  fi
done

if [[ "${#missing[@]}" -gt 0 ]]; then
  echo "Missing macOS TestFlight signing secrets: ${missing[*]}" >&2
  exit 1
fi

eval "$(python3 "$ROOT_DIR/scripts/ci/build_version.py" --format shell)"
app_version="$DISPLAY_VERSION"
app_build="$BUILD_NUMBER"
BUILD_DATE_LINE="$(sed -n 's/^build-date:[[:space:]]*//p' "$ROOT_DIR/pubspec.yaml" | head -n 1)"
BUILD_ID_LINE="$(sed -n 's/^build-id:[[:space:]]*//p' "$ROOT_DIR/pubspec.yaml" | head -n 1)"
GIT_BUILD_DATE="$(cd "$ROOT_DIR" && git show -s --format=%cs HEAD 2>/dev/null || true)"
GIT_BUILD_COMMIT="$(cd "$ROOT_DIR" && git rev-parse --short HEAD 2>/dev/null || true)"
app_build_date="${GIT_BUILD_DATE:-${BUILD_DATE_LINE:-unknown}}"
app_build_commit="${GIT_BUILD_COMMIT:-${BUILD_ID_LINE:-unknown}}"

tmp_dir="$(mktemp -d "${RUNNER_TEMP:-/tmp}/xworkmate-macos-app-store.XXXXXX")"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

apple_setup_signing_keychain

apple_decode_base64() {
  if base64 --help 2>&1 | grep -q -- '--decode'; then
    base64 --decode
  else
    base64 -D
  fi
}

profile_dir="$HOME/Library/MobileDevice/Provisioning Profiles"
profile_path="$profile_dir/xworkmate-macos.mobileprovision"
mkdir -p "$profile_dir"
printf '%s' "$APPLE_MAC_PROVISION_PROFILE_BASE64" | apple_decode_base64 > "$profile_path"
apple_register_cleanup "rm -f \"$profile_path\""

mkdir -p "$DIST_DIR"
archive_path="$tmp_dir/$APP_NAME.xcarchive"
export_options_path="$tmp_dir/ExportOptions.plist"
sed "s|\${EXPORT_METHOD}|app-store|g" "$ROOT_DIR/ios/ExportOptions.plist" > "$export_options_path"

flutter pub get
flutter build macos --release \
  --build-name="$PLATFORM_RELEASE_VERSION" \
  --build-number="$app_build" \
  --dart-define="XWORKMATE_DISPLAY_VERSION=$app_version" \
  --dart-define="XWORKMATE_BUILD_NUMBER=$app_build" \
  --dart-define="XWORKMATE_BUILD_DATE=$app_build_date" \
  --dart-define="XWORKMATE_BUILD_COMMIT=$app_build_commit" \
  "$APP_STORE_DEFINE"

xcodebuild archive \
  -workspace "$ROOT_DIR/macos/Runner.xcworkspace" \
  -scheme Runner \
  -configuration Release \
  -archivePath "$archive_path" \
  DEVELOPMENT_TEAM="N3G9T67W78"

xcodebuild -exportArchive \
  -archivePath "$archive_path" \
  -exportPath "$DIST_DIR" \
  -exportOptionsPlist "$export_options_path"

if ! compgen -G "$DIST_DIR/*.pkg" >/dev/null; then
  echo "No macOS TestFlight pkg was produced under $DIST_DIR" >&2
  exit 1
fi

echo "macOS TestFlight pkg: $(find "$DIST_DIR" -maxdepth 1 -name '*.pkg' | head -n 1)"
