#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dist_dir="$root_dir/dist/android"
key_properties="$root_dir/android/key.properties"
keystore_path="$root_dir/android/upload-keystore.jks"
generated_signing=false

cleanup() {
  if [[ "$generated_signing" == "true" ]]; then
    rm -f "$key_properties" "$keystore_path"
  fi
}
trap cleanup EXIT

if [[ -n "${ANDROID_KEYSTORE_BASE64:-}" && -n "${ANDROID_KEYSTORE_PASSWORD:-}" && -n "${ANDROID_KEY_ALIAS:-}" && -n "${ANDROID_KEY_PASSWORD:-}" ]]; then
  if [[ -e "$key_properties" || -e "$keystore_path" ]]; then
    echo "Refusing to overwrite existing Android signing files." >&2
    exit 1
  fi
  umask 077
  generated_signing=true
  printf '%s' "$ANDROID_KEYSTORE_BASE64" | base64 --decode > "$keystore_path"
  cat > "$key_properties" <<PROPERTIES
storePassword=$ANDROID_KEYSTORE_PASSWORD
keyPassword=$ANDROID_KEY_PASSWORD
keyAlias=$ANDROID_KEY_ALIAS
storeFile=$keystore_path
PROPERTIES
elif [[ ! -f "$key_properties" ]]; then
  echo "Android release signing is required; the upload-key contract is incomplete." >&2
  echo "Provide signing through the CI environment or android/key.properties. Use flutter build apk --debug for local verification." >&2
  exit 1
fi

mkdir -p "$dist_dir"
flutter pub get
flutter build apk --release
flutter build appbundle --release
cp "$root_dir/build/app/outputs/flutter-apk/app-release.apk" "$dist_dir/xworkmate-android-arm64.apk"
cp "$root_dir/build/app/outputs/bundle/release/app-release.aab" "$dist_dir/xworkmate-android.aab"
