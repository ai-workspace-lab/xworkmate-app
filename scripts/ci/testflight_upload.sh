#!/usr/bin/env bash
set -euo pipefail

platform="${1:?platform is required}"
artifact_root="${2:?artifact root is required}"

required_vars=(
  APP_STORE_CONNECT_API_KEY_ID
  APP_STORE_CONNECT_ISSUER_ID
  APP_STORE_CONNECT_API_KEY_P8_BASE64
)

missing=()
for var_name in "${required_vars[@]}"; do
  if [[ -z "${!var_name:-}" ]]; then
    missing+=("$var_name")
  fi
done

if [[ "${#missing[@]}" -gt 0 ]]; then
  echo "Missing App Store Connect secrets: ${missing[*]}" >&2
  exit 1
fi

if ! command -v xcrun >/dev/null 2>&1; then
  echo "xcrun is required to upload TestFlight artifacts." >&2
  exit 1
fi

apple_decode_base64() {
  if base64 --help 2>&1 | grep -q -- '--decode'; then
    base64 --decode
  else
    base64 -D
  fi
}

tmp_dir="$(mktemp -d "${RUNNER_TEMP:-/tmp}/xworkmate-testflight.XXXXXX")"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

private_keys_dir="$tmp_dir/private_keys"
mkdir -p "$private_keys_dir"

p8_path="$private_keys_dir/AuthKey_${APP_STORE_CONNECT_API_KEY_ID}.p8"
printf '%s' "$APP_STORE_CONNECT_API_KEY_P8_BASE64" | apple_decode_base64 > "$p8_path"

case "$platform" in
  ios)
    artifact_file="$(find "$artifact_root" -type f -name '*.ipa' | head -n 1)"
    ;;
  macos)
    artifact_file="$(find "$artifact_root" -type f -name '*.pkg' | head -n 1)"
    ;;
  *)
    echo "Unsupported TestFlight platform: $platform" >&2
    exit 1
    ;;
esac
if [[ -z "$artifact_file" ]]; then
  echo "No ipa/pkg artifact found under $artifact_root" >&2
  exit 1
fi

export API_PRIVATE_KEYS_DIR="$private_keys_dir"

if [[ "$platform" == "ios" ]]; then
  xcrun altool \
    --upload-app \
    -f "$artifact_file" \
    --api-key "$APP_STORE_CONNECT_API_KEY_ID" \
    --api-issuer "$APP_STORE_CONNECT_ISSUER_ID" \
    --show-progress
else
  xcrun altool \
    --upload-package "$artifact_file" \
    --api-key "$APP_STORE_CONNECT_API_KEY_ID" \
    --api-issuer "$APP_STORE_CONNECT_ISSUER_ID" \
    --show-progress
fi
