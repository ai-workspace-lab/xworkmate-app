#!/usr/bin/env bash
set -euo pipefail

platform="${1:?platform is required}"

case "$platform" in
  linux)
    sudo apt-get update
    sudo apt-get install -y \
      clang \
      cmake \
      ninja-build \
      libgtk-3-dev \
      pkg-config \
      libx11-dev \
      libgl1-mesa-dev \
      libayatana-appindicator3-dev \
      dpkg-dev \
      rpm \
      imagemagick
    ;;
  android)
    sudo apt-get update
    sudo apt-get install -y clang cmake ninja-build libgtk-3-dev pkg-config libx11-dev libgl1-mesa-dev

    android_sdk_root="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-/usr/local/lib/android/sdk}}"
    export ANDROID_SDK_ROOT="$android_sdk_root"
    export ANDROID_HOME="$android_sdk_root"

    {
      echo "ANDROID_SDK_ROOT=$android_sdk_root"
      echo "ANDROID_HOME=$android_sdk_root"
    } >> "$GITHUB_ENV"

    for candidate in \
      "$android_sdk_root/cmdline-tools/latest/bin/sdkmanager" \
      "$android_sdk_root/cmdline-tools/bin/sdkmanager" \
      "$android_sdk_root/tools/bin/sdkmanager"; do
      if [[ -x "$candidate" ]]; then
        sdkmanager="$candidate"
        break
      fi
    done

    if [[ -z "${sdkmanager:-}" ]]; then
      echo "Android sdkmanager not found under $android_sdk_root" >&2
      exit 1
    fi

    yes | "$sdkmanager" --licenses >/dev/null 2>&1 || true
    "$sdkmanager" "platform-tools" "platforms;android-35" "build-tools;35.0.0" "ndk;27.1.12297006"

    flutter_bin="$(command -v flutter)"
    flutter_root="$(cd "$(dirname "$flutter_bin")/.." && pwd)"
    app_version="$(sed -n 's/^version:[[:space:]]*//p' pubspec.yaml | head -n 1)"
    app_version="${app_version%%+*}"
    version_code="${GITHUB_RUN_NUMBER:-1}"

    cat > android/local.properties <<EOF
sdk.dir=$android_sdk_root
flutter.sdk=$flutter_root
flutter.buildMode=release
flutter.versionName=$app_version
flutter.versionCode=$version_code
EOF
    ;;
  macos)
    brew install cocoapods create-dmg
    ;;
  ios)
    brew install cocoapods
    ;;
  windows)
    dotnet tool install --global wix --version 4.0.4
    echo "$HOME/.dotnet/tools" >> "$GITHUB_PATH"
    ;;
  *)
    echo "Unsupported platform: $platform" >&2
    exit 1
    ;;
esac
