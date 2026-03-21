#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dist_dir="$root_dir/dist/ios"
export_method="${APPLE_EXPORT_METHOD:-ad-hoc}"

mkdir -p "$dist_dir"

decode_base64() {
  if base64 --help 2>&1 | grep -q -- '--decode'; then
    base64 --decode
  else
    base64 -D
  fi
}

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

tmp_dir="$(mktemp -d "${RUNNER_TEMP:-/tmp}/xworkmate-ios.XXXXXX")"
keychain_name="xworkmate-build.keychain-db"
keychain_path="$HOME/Library/Keychains/$keychain_name"
cert_path="$tmp_dir/dist-cert.p12"
profile_path="$tmp_dir/profile.mobileprovision"
export_options_path="$tmp_dir/ExportOptions.plist"

cleanup() {
  security delete-keychain "$keychain_path" >/dev/null 2>&1 || true
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

printf '%s' "$APPLE_CERT_P12_BASE64" | decode_base64 > "$cert_path"
printf '%s' "$APPLE_PROVISION_PROFILE_BASE64" | decode_base64 > "$profile_path"

security create-keychain -p "$APPLE_KEYCHAIN_PASSWORD" "$keychain_name"
security set-keychain-settings -lut 21600 "$keychain_path"
security unlock-keychain -p "$APPLE_KEYCHAIN_PASSWORD" "$keychain_path"
security import "$cert_path" -P "$APPLE_CERT_PASSWORD" -A -t cert -f pkcs12 -k "$keychain_path"
security list-keychains -d user -s "$keychain_path"
security set-key-partition-list -S apple-tool:,apple: -s -k "$APPLE_KEYCHAIN_PASSWORD" "$keychain_path"

mkdir -p "$HOME/Library/MobileDevice/Provisioning Profiles"
cp "$profile_path" "$HOME/Library/MobileDevice/Provisioning Profiles/xworkmate.mobileprovision"

sed "s|\${EXPORT_METHOD}|$export_method|g" "$root_dir/ios/ExportOptions.plist" > "$export_options_path"

flutter pub get
flutter build ipa --release --export-options-plist="$export_options_path"

find "$root_dir/build/ios/ipa" -maxdepth 1 -name '*.ipa' -exec cp {} "$dist_dir/" \;

if ! compgen -G "$dist_dir/*.ipa" >/dev/null; then
  echo "No IPA was produced under $dist_dir" >&2
  exit 1
fi
