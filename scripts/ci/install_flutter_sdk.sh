#!/usr/bin/env bash
set -euo pipefail

version="${1:?flutter version is required}"
runner_temp="${RUNNER_TEMP:-/tmp}"
install_root="$runner_temp/flutter-sdk"
archive_name="flutter_linux_${version}-stable.tar.xz"

case "${RUNNER_OS:-$(uname -s)}" in
  Linux)
    archive_name="flutter_linux_${version}-stable.tar.xz"
    download_url="https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/${archive_name}"
    ;;
  macOS|Darwin)
    if [[ "$(uname -m)" == "arm64" ]]; then
      archive_name="flutter_macos_arm64_${version}-stable.zip"
    else
      archive_name="flutter_macos_${version}-stable.zip"
    fi
    download_url="https://storage.googleapis.com/flutter_infra_release/releases/stable/macos/${archive_name}"
    ;;
  *)
    echo "Unsupported OS for Flutter install: ${RUNNER_OS:-$(uname -s)}" >&2
    exit 1
    ;;
esac

mkdir -p "$install_root"

if [[ ! -x "$install_root/flutter/bin/flutter" ]]; then
  archive_path="$runner_temp/$archive_name"
  curl -fsSL "$download_url" -o "$archive_path"
  rm -rf "$install_root/flutter"
  case "$archive_name" in
    *.tar.xz)
      tar -xJf "$archive_path" -C "$install_root"
      ;;
    *.zip)
      unzip -q "$archive_path" -d "$install_root"
      ;;
  esac
fi

echo "$install_root/flutter/bin" >> "$GITHUB_PATH"
"$install_root/flutter/bin/flutter" --disable-analytics
"$install_root/flutter/bin/flutter" config --no-analytics
"$install_root/flutter/bin/flutter" --version
