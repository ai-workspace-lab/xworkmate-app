#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APK_PATH="${ROOT_DIR}/build/app/outputs/flutter-apk/app-release.apk"
AAB_PATH="${ROOT_DIR}/build/app/outputs/bundle/release/app-release.aab"
EXPECTED_PACKAGE="plus.svc.xworkmate"

[[ -f "$APK_PATH" ]] || { echo "Release APK not found: $APK_PATH" >&2; exit 1; }
[[ -f "$AAB_PATH" ]] || { echo "Release App Bundle not found: $AAB_PATH" >&2; exit 1; }

ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
if [[ -z "$ANDROID_SDK_ROOT" && -f "$ROOT_DIR/android/local.properties" ]]; then
  ANDROID_SDK_ROOT="$(sed -n 's/^sdk.dir=//p' "$ROOT_DIR/android/local.properties" | head -n 1)"
fi
APKSIGNER=""
if [[ -n "$ANDROID_SDK_ROOT" ]]; then
  APKSIGNER="$(find "$ANDROID_SDK_ROOT/build-tools" -type f -name apksigner 2>/dev/null | sort | tail -n 1 || true)"
fi
if [[ -z "$APKSIGNER" ]]; then
  APKSIGNER="$(command -v apksigner || true)"
fi
[[ -n "$APKSIGNER" ]] || { echo "apksigner was not found; set ANDROID_SDK_ROOT or install Android build-tools." >&2; exit 1; }

APK_CERTS="$("$APKSIGNER" verify --verbose --print-certs "$APK_PATH" 2>&1)"
if grep -qi 'Android Debug' <<<"$APK_CERTS"; then
  echo "Release APK is signed with the Android debug certificate; it cannot be uploaded to Google Play." >&2
  exit 1
fi
"$APKSIGNER" verify --verbose "$APK_PATH" >/dev/null

JARSIGNER="$(command -v jarsigner || true)"
[[ -n "$JARSIGNER" ]] || { echo "jarsigner was not found in JAVA_HOME/PATH." >&2; exit 1; }
AAB_CERTS="$("$JARSIGNER" -verify -verbose:certs "$AAB_PATH" 2>&1)"
if ! grep -qE 'jar verified|jar 已验证' <<<"$AAB_CERTS"; then
  echo "Release App Bundle failed jarsigner verification." >&2
  exit 1
fi
if grep -qi 'Android Debug' <<<"$AAB_CERTS"; then
  echo "Release App Bundle is signed with the Android debug certificate; it cannot be uploaded to Google Play." >&2
  exit 1
fi

if command -v aapt2 >/dev/null 2>&1; then
  BADGING="$(aapt2 dump badging "$APK_PATH")"
  grep -q "package: name='$EXPECTED_PACKAGE'" <<<"$BADGING" || {
    echo "APK package name does not match $EXPECTED_PACKAGE." >&2
    exit 1
  }
fi

echo ">>> Android release signing verified for Google Play upload."
echo "    APK: $APK_PATH"
echo "    AAB: $AAB_PATH"
