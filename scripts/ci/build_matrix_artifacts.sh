#!/usr/bin/env bash
set -euo pipefail

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
    flutter build windows --release
    pwsh -File ./scripts/package-windows-msi.ps1 -Arch "$arch"
    ;;
  ios)
    if [[ "$should_release" == "true" ]]; then
      bash ./scripts/package-ios-ipa.sh
    else
      echo "Release secrets not required for non-release runs; building unsigned iOS app bundle."
      flutter build ios --release --no-codesign
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
