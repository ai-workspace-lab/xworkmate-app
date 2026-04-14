#!/usr/bin/env bash

apple_decode_base64() {
  if base64 --help 2>&1 | grep -q -- '--decode'; then
    base64 --decode
  else
    base64 -D
  fi
}

apple_require_signing_vars() {
  local missing=()
  local var_name=""

  for var_name in "$@"; do
    if [[ -z "${!var_name:-}" ]]; then
      missing+=("$var_name")
    fi
  done

  if [[ "${#missing[@]}" -gt 0 ]]; then
    echo "Missing Apple signing secrets: ${missing[*]}" >&2
    return 1
  fi
}

apple_register_cleanup() {
  local command="$1"
  APPLE_SIGNING_CLEANUP_COMMANDS+=("$command")
}

apple_run_cleanup() {
  local status=$?
  local index=0

  for (( index=${#APPLE_SIGNING_CLEANUP_COMMANDS[@]}-1; index>=0; index-- )); do
    eval "${APPLE_SIGNING_CLEANUP_COMMANDS[index]}" >/dev/null 2>&1 || true
  done

  return "$status"
}

apple_setup_signing_keychain() {
  apple_require_signing_vars \
    APPLE_CERT_P12_BASE64 \
    APPLE_CERT_PASSWORD \
    APPLE_KEYCHAIN_PASSWORD

  local tmp_dir
  tmp_dir="$(mktemp -d "${RUNNER_TEMP:-/tmp}/xworkmate-apple.XXXXXX")"
  local keychain_name="xworkmate-build.keychain-db"
  local keychain_path="$HOME/Library/Keychains/$keychain_name"
  local cert_path="$tmp_dir/dist-cert.p12"

  printf '%s' "$APPLE_CERT_P12_BASE64" | apple_decode_base64 > "$cert_path"

  security create-keychain -p "$APPLE_KEYCHAIN_PASSWORD" "$keychain_name"
  security set-keychain-settings -lut 21600 "$keychain_path"
  security unlock-keychain -p "$APPLE_KEYCHAIN_PASSWORD" "$keychain_path"
  security import "$cert_path" -P "$APPLE_CERT_PASSWORD" -A -t cert -f pkcs12 -k "$keychain_path"
  security list-keychains -d user -s "$keychain_path"
  security set-key-partition-list -S apple-tool:,apple: -s -k "$APPLE_KEYCHAIN_PASSWORD" "$keychain_path"

  export APPLE_SIGNING_TMP_DIR="$tmp_dir"
  export APPLE_SIGNING_KEYCHAIN_PATH="$keychain_path"

  apple_register_cleanup "security delete-keychain \"$keychain_path\""
  apple_register_cleanup "rm -rf \"$tmp_dir\""
}

apple_install_provision_profile() {
  local profile_name="${1:-xworkmate.mobileprovision}"

  apple_require_signing_vars APPLE_PROVISION_PROFILE_BASE64

  local profile_dir="$HOME/Library/MobileDevice/Provisioning Profiles"
  local profile_path="$profile_dir/$profile_name"

  mkdir -p "$profile_dir"
  printf '%s' "$APPLE_PROVISION_PROFILE_BASE64" | apple_decode_base64 > "$profile_path"

  export APPLE_SIGNING_PROFILE_PATH="$profile_path"
  apple_register_cleanup "rm -f \"$profile_path\""
}
