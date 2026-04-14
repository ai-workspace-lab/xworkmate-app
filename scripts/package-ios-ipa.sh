#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dist_dir="$root_dir/dist/ios"
export_method="${APPLE_EXPORT_METHOD:-ad-hoc}"
app_store_define="${APP_STORE_DEFINE:---dart-define=XWORKMATE_APP_STORE=${XWORKMATE_APP_STORE:-true}}"
source "$root_dir/scripts/ci/apple_signing.sh"
APPLE_SIGNING_CLEANUP_COMMANDS=()
trap apple_run_cleanup EXIT

mkdir -p "$dist_dir"

required_vars=(
  APPLE_CERT_P12_BASE64
  APPLE_CERT_PASSWORD
  APPLE_PROVISION_PROFILE_BASE64
  APPLE_KEYCHAIN_PASSWORD
)

missing=()
for var_name in "${required_vars[@]}"; do
  if [[ -z "${!var_name:-}" ]]; then
    missing+=("$var_name")
  fi
done

if [[ "${#missing[@]}" -gt 0 ]]; then
  echo "Missing iOS signing secrets: ${missing[*]}" >&2
  exit 1
fi

eval "$(python3 "$root_dir/scripts/ci/build_version.py" --format shell)"
app_version="$DISPLAY_VERSION"
app_build="$BUILD_NUMBER"
apple_setup_signing_keychain
apple_install_provision_profile "xworkmate.mobileprovision"

tmp_dir="$APPLE_SIGNING_TMP_DIR"
export_options_path="$tmp_dir/ExportOptions.plist"

sed "s|\${EXPORT_METHOD}|$export_method|g" "$root_dir/ios/ExportOptions.plist" > "$export_options_path"

flutter pub get
flutter build ipa --release \
  --build-name="$PLATFORM_RELEASE_VERSION" \
  --build-number="$app_build" \
  --dart-define="XWORKMATE_DISPLAY_VERSION=$app_version" \
  --dart-define="XWORKMATE_BUILD_NUMBER=$app_build" \
  "$app_store_define" \
  --export-options-plist="$export_options_path"

archive_path="$root_dir/build/ios/archive/Runner.xcarchive"
if [[ -d "$archive_path" ]]; then
  bash "$root_dir/scripts/check-apple-export-compliance.sh" "$archive_path"
fi

find "$root_dir/build/ios/ipa" -maxdepth 1 -name '*.ipa' -exec cp {} "$dist_dir/" \;

if ! compgen -G "$dist_dir/*.ipa" >/dev/null; then
  echo "No IPA was produced under $dist_dir" >&2
  exit 1
fi
