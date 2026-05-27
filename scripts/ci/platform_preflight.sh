#!/usr/bin/env bash
set -euo pipefail

platform="${1:?platform is required}"
should_release="${2:-false}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

emit_output() {
  local key="$1"
  local value="$2"

  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    printf '%s=%s\n' "$key" "$value" >> "$GITHUB_OUTPUT"
  else
    printf '%s=%s\n' "$key" "$value"
  fi
}

set_build_state() {
  local should_build="$1"
  local reason="$2"

  emit_output "should_build_platform" "$should_build"
  emit_output "skip_reason" "$reason"

  if [[ "$should_build" == "true" ]]; then
    echo "Preflight passed for $platform."
  else
    echo "Skipping $platform lane: $reason"
  fi
}

case "$platform" in
  linux)
    set_build_state "true" ""
    ;;
  windows)
    set_build_state "true" ""
    ;;
  macos)
    required_vars=(
      APPLE_CERT_P12_BASE64
      APPLE_CERT_PASSWORD
      APPLE_KEYCHAIN_PASSWORD
    )

    missing=()
    for var_name in "${required_vars[@]}"; do
      if [[ -z "${!var_name:-}" ]]; then
        missing+=("$var_name")
      fi
    done

    if [[ "${#missing[@]}" -gt 0 ]]; then
      set_build_state "false" "missing macOS signing secrets: ${missing[*]}"
      exit 0
    fi

    set_build_state "true" ""
    ;;
  ios)
    if [[ "$should_release" != "true" ]]; then
      set_build_state "true" ""
      exit 0
    fi

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
      set_build_state "false" "missing iOS signing secrets: ${missing[*]}"
      exit 0
    fi

    set_build_state "true" ""
    ;;
  android)
    set_build_state "true" ""
    ;;
  *)
    echo "Unsupported platform: $platform" >&2
    exit 1
    ;;
esac
