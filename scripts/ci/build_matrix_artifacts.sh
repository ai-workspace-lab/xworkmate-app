#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"
eval "$(python3 "$repo_root/scripts/ci/build_version.py" --format shell)"
platform="${1:?platform is required}"
arch="${2:?arch is required}"
should_release="${3:-false}"

flutter pub get

case "$platform" in
  linux)
    bash ./scripts/package-linux.sh
    ;;
  macos)
    bash ./scripts/package-flutter-mac-app.sh
    mkdir -p dist/macos
    find dist -maxdepth 1 -name '*.dmg' -exec mv {} dist/macos/ \;
    ;;
  windows)
    flutter build windows --release \
      --build-name="$PLATFORM_RELEASE_VERSION" \
      --build-number="$BUILD_NUMBER"
    pwsh -File ./scripts/package-windows-msi.ps1 -Arch "$arch"
    ;;
  ios)
    if [[ "$should_release" == "true" ]]; then
      bash ./scripts/package-ios-ipa.sh
    else
      echo "Release secrets not required for non-release runs; building unsigned iOS app bundle."
      flutter build ios --release --no-codesign \
        --build-name="$PLATFORM_RELEASE_VERSION" \
        --build-number="$BUILD_NUMBER" \
        --dart-define="XWORKMATE_DISPLAY_VERSION=$DISPLAY_VERSION" \
        --dart-define="XWORKMATE_BUILD_NUMBER=$BUILD_NUMBER"
      mkdir -p dist/ios
      (
        cd build/ios/iphoneos
        rm -f XWorkmate.app.zip
        zip -qry XWorkmate.app.zip Runner.app
        mv XWorkmate.app.zip ../../../dist/ios/
      )
    fi
    ;;
  android)
    bash ./scripts/package-android-apk.sh
    ;;
  *)
    echo "Unsupported platform: $platform" >&2
    exit 1
    ;;
esac
