#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"
eval "$(python3 "$repo_root/scripts/ci/build_version.py" --format shell)"
platform="${1:?platform is required}"
arch="${2:?arch is required}"
package_kind="${3:-}"
should_release="${4:-false}"

flutter pub get

case "$platform" in
  linux)
    bash ./scripts/package-linux.sh
    ;;
  macos)
    case "$package_kind" in
      dmg)
        bash ./scripts/package-flutter-mac-app.sh
        mkdir -p dist/macos
        find dist -maxdepth 1 -name '*.dmg' -exec mv {} dist/macos/ \;
        ;;
      app-store-pkg)
        bash ./scripts/package-macos-app-store-pkg.sh
        mkdir -p dist/macos-app-store
        find dist -maxdepth 1 -name '*.pkg' -exec mv {} dist/macos-app-store/ \;
        ;;
      *)
        echo "Unsupported macOS package kind: $package_kind" >&2
        exit 1
        ;;
    esac
    ;;
  windows)
    flutter build windows --release \
      --build-name="$PLATFORM_RELEASE_VERSION" \
      --build-number="$BUILD_NUMBER"
    pwsh -File ./scripts/package-windows-msi.ps1 -Arch "$arch"
    ;;
  ios)
    ios_signing_secrets=(
      APPLE_CERT_P12_BASE64
      APPLE_CERT_PASSWORD
      APPLE_PROVISION_PROFILE_BASE64
      APPLE_KEYCHAIN_PASSWORD
    )
    ios_missing=()
    for var_name in "${ios_signing_secrets[@]}"; do
      if [[ -z "${!var_name:-}" ]]; then
        ios_missing+=("$var_name")
      fi
    done

    if [[ "${#ios_missing[@]}" -gt 0 ]]; then
      echo "Apple signing secrets unavailable (missing: ${ios_missing[*]}); building unsigned iOS app bundle."
      build_unsigned_ios_bundle=1
    elif [[ "$should_release" == "true" ]]; then
      build_unsigned_ios_bundle=0
    else
      echo "Release not requested; building unsigned iOS app bundle."
      build_unsigned_ios_bundle=1
    fi

    if [[ "$build_unsigned_ios_bundle" -eq 1 ]]; then
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
    else
      bash ./scripts/package-ios-ipa.sh
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
