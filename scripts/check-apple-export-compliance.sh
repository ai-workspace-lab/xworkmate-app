#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IOS_SOURCE_PLIST="$ROOT_DIR/ios/Runner/Info.plist"
MACOS_SOURCE_PLIST="$ROOT_DIR/macos/Runner/Info.plist"
TARGET_PATH="${1:-}"

usage() {
  cat <<'EOF'
Usage:
  scripts/check-apple-export-compliance.sh [artifact-path]

Without an artifact path, the script validates the source plist values for iOS
and macOS. With an artifact path, it also validates the built bundle/archive:

Supported artifact paths:
  - *.xcarchive
  - *.app
  - path to an Info.plist file
EOF
}

if [[ "${TARGET_PATH:-}" == "-h" || "${TARGET_PATH:-}" == "--help" ]]; then
  usage
  exit 0
fi

read_bool() {
  local plist_path="$1"
  local key="$2"
  python3 - "$plist_path" "$key" <<'PY'
import plistlib
import sys

plist_path = sys.argv[1]
key = sys.argv[2]

with open(plist_path, "rb") as handle:
    data = plistlib.load(handle)

value = data.get(key, None)
if value is None:
    print("__MISSING__")
elif value is True:
    print("true")
elif value is False:
    print("false")
else:
    print(str(value).strip().lower())
PY
}

resolve_artifact_plist() {
  local input_path="$1"
  if [[ -f "$input_path" && "$(basename "$input_path")" == "Info.plist" ]]; then
    printf '%s\n' "$input_path"
    return 0
  fi
  if [[ -d "$input_path" && "$input_path" == *.xcarchive ]]; then
    local plist_path=""
    plist_path="$(find "$input_path/Products/Applications" -maxdepth 3 -name Info.plist | head -n 1)"
    if [[ -n "$plist_path" ]]; then
      printf '%s\n' "$plist_path"
      return 0
    fi
  fi
  if [[ -d "$input_path" && "$input_path" == *.app ]]; then
    if [[ -f "$input_path/Contents/Info.plist" ]]; then
      printf '%s\n' "$input_path/Contents/Info.plist"
      return 0
    fi
    if [[ -f "$input_path/Info.plist" ]]; then
      printf '%s\n' "$input_path/Info.plist"
      return 0
    fi
  fi
  return 1
}

report_value() {
  local label="$1"
  local plist_path="$2"
  local value="$3"
  echo "$label: $plist_path"
  echo "  ITSAppUsesNonExemptEncryption = $value"
}

assert_false() {
  local label="$1"
  local plist_path="$2"
  local value="$3"
  if [[ "$value" != "false" ]]; then
    echo "Export compliance check failed for $label" >&2
    report_value "$label" "$plist_path" "$value" >&2
    return 1
  fi
}

source_ios_value="$(read_bool "$IOS_SOURCE_PLIST" ITSAppUsesNonExemptEncryption)"
source_macos_value="$(read_bool "$MACOS_SOURCE_PLIST" ITSAppUsesNonExemptEncryption)"

assert_false "iOS source" "$IOS_SOURCE_PLIST" "$source_ios_value"
assert_false "macOS source" "$MACOS_SOURCE_PLIST" "$source_macos_value"

report_value "iOS source" "$IOS_SOURCE_PLIST" "$source_ios_value"
report_value "macOS source" "$MACOS_SOURCE_PLIST" "$source_macos_value"

if [[ -z "$TARGET_PATH" ]]; then
  exit 0
fi

ARTIFACT_PLIST="$(resolve_artifact_plist "$TARGET_PATH" || true)"
if [[ -z "$ARTIFACT_PLIST" ]]; then
  echo "Unsupported artifact path: $TARGET_PATH" >&2
  usage >&2
  exit 2
fi

artifact_value="$(read_bool "$ARTIFACT_PLIST" ITSAppUsesNonExemptEncryption)"
report_value "Artifact" "$ARTIFACT_PLIST" "$artifact_value"
assert_false "Artifact" "$ARTIFACT_PLIST" "$artifact_value"

echo "Export compliance check passed."
