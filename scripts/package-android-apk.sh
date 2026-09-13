#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dist_dir="$root_dir/dist/android"
key_properties="$root_dir/android/key.properties"
keystore_path="$root_dir/android/upload-keystore.jks"
require_signing="${1:-${REQUIRE_ANDROID_SIGNING:-false}}"

mkdir -p "$dist_dir"

cleanup() {
  rm -f "$key_properties" "$keystore_path"
}
trap cleanup EXIT

if [[ -n "${ANDROID_KEYSTORE_BASE64:-}" && -n "${ANDROID_KEYSTORE_PASSWORD:-}" && -n "${ANDROID_KEY_ALIAS:-}" && -n "${ANDROID_KEY_PASSWORD:-}" ]]; then
  printf '%s' "$ANDROID_KEYSTORE_BASE64" | base64 --decode > "$keystore_path"
  cat > "$key_properties" <<EOF
storePassword=$ANDROID_KEYSTORE_PASSWORD
keyPassword=$ANDROID_KEY_PASSWORD
keyAlias=$ANDROID_KEY_ALIAS
storeFile=$keystore_path
EOF
elif [[ "$require_signing" == "true" ]]; then
  echo "Android release signing is required, but the keystore contract is incomplete." >&2
  echo "Set ANDROID_KEYSTORE_BASE64, ANDROID_KEYSTORE_PASSWORD, ANDROID_KEY_ALIAS, and ANDROID_KEY_PASSWORD." >&2
  exit 1
else
  echo "Android signing secrets are not fully set; using debug signing fallback for verification builds."
fi

flutter pub get
flutter build apk --release
flutter build appbundle --release
cp "$root_dir/build/app/outputs/flutter-apk/app-release.apk" "$dist_dir/xworkmate-android-arm64.apk"
cp "$root_dir/build/app/outputs/bundle/release/app-release.aab" "$dist_dir/xworkmate-android.aab"
