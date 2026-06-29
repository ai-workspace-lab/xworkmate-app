#!/usr/bin/env bash
set -euo pipefail

REPO=${XWORKMATE_INSTALL_REPO:-"x-evor/xworkmate-app"}
RELEASE_TAG=${XWORKMATE_INSTALL_RELEASE_TAG:-"latest"}
GITHUB_API=${XWORKMATE_INSTALL_GITHUB_API:-"https://api.github.com"}
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/xworkmate-install.XXXXXX")"
MOUNT_POINT=""

cleanup() {
  if [[ -n "$MOUNT_POINT" ]]; then
    hdiutil detach "$MOUNT_POINT" -quiet >/dev/null 2>&1 || true
  fi
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

info() { printf '[INFO] %s\n' "$*" >&2; }
die() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

need() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

release_json_url() {
  if [[ "$RELEASE_TAG" == "latest" ]]; then
    printf '%s/repos/%s/releases/latest\n' "$GITHUB_API" "$REPO"
  else
    printf '%s/repos/%s/releases/tags/%s\n' "$GITHUB_API" "$REPO" "$RELEASE_TAG"
  fi
}

github_curl() {
  local accept="$1"
  shift
  local token="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
  local -a headers=(
    -H "Accept: $accept"
    -H "X-GitHub-Api-Version: 2022-11-28"
  )

  if [[ -n "$token" ]]; then
    headers+=(-H "Authorization: Bearer $token")
  fi
  curl "${headers[@]}" "$@"
}

pick_asset() {
  local metadata_file="$1"
  local pattern="$2"
  python3 - "$metadata_file" "$pattern" <<'PY'
import json
import re
import sys
from pathlib import Path

metadata_path = Path(sys.argv[1])
pattern = re.compile(sys.argv[2])
data = json.loads(metadata_path.read_text(encoding="utf-8"))
for asset in data.get("assets", []):
    name = asset.get("name", "")
    if pattern.search(name):
        print(f'{asset.get("url", "")}\t{name}')
        raise SystemExit(0)
raise SystemExit(1)
PY
}

download_asset() {
  local asset_url="$1"
  local output_path="$2"

  github_curl application/octet-stream \
    -fL --retry 5 --retry-all-errors --continue-at - \
    -o "$output_path" "$asset_url"
}

install_macos_dmg() {
  local dmg_url="$1"
  local dmg_path="$TMP_DIR/XWorkmate.dmg"
  local target_app="/Applications/XWorkmate.app"

  MOUNT_POINT="$TMP_DIR/mount"
  mkdir -p "$MOUNT_POINT"
  info "Downloading macOS DMG..."
  download_asset "$dmg_url" "$dmg_path"
  info "Mounting DMG..."
  hdiutil attach "$dmg_path" -mountpoint "$MOUNT_POINT" -nobrowse -readonly -quiet

  local source_app="$MOUNT_POINT/XWorkmate.app"
  [[ -d "$source_app" ]] || die "DMG does not contain XWorkmate.app"
  if [[ -d "$target_app" ]]; then
    info "Replacing existing app at $target_app"
    rm -rf "$target_app"
  fi
  info "Installing to $target_app"
  ditto "$source_app" "$target_app"
  xattr -dr com.apple.quarantine "$target_app" 2>/dev/null || true
  info "Installed $target_app"
}

install_linux_pkg() {
  local pkg_url="$1"
  local pkg_name="$2"
  local pkg_path="$TMP_DIR/package"

  download_asset "$pkg_url" "$pkg_path"
  need sudo
  if [[ "$pkg_name" == *.deb ]]; then
    info "Installing Debian package..."
    sudo dpkg -i "$pkg_path" || sudo apt-get -f install -y
  elif [[ "$pkg_name" == *.rpm ]]; then
    info "Installing RPM package..."
    if command -v dnf >/dev/null 2>&1; then
      sudo dnf install -y "$pkg_path"
    else
      sudo rpm -Uvh "$pkg_path"
    fi
  else
    die "Unsupported Linux asset: $pkg_name"
  fi
}

main() {
  local release_json_path="$TMP_DIR/release.json"
  local asset_name_pattern
  local asset
  local asset_name
  local asset_url

  need curl
  need python3

  info "Resolving release for $REPO"
  github_curl application/vnd.github+json \
    -fsSL "$(release_json_url)" -o "$release_json_path"

  case "$(uname -s)" in
    Darwin)
      asset_name_pattern='^XWorkmate-[^/]+\.dmg$'
      ;;
    Linux)
      case "$(uname -m)" in
        x86_64|amd64) ;;
        *) die "Linux packages are only available for amd64: $(uname -m)" ;;
      esac
      if command -v dpkg >/dev/null 2>&1; then
        asset_name_pattern='^xworkmate_[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9]+)?_amd64\.deb$'
      elif command -v rpm >/dev/null 2>&1; then
        asset_name_pattern='^xworkmate-[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9]+)?-1\.x86_64\.rpm$'
      else
        die "Neither dpkg nor rpm found"
      fi
      ;;
    *)
      die "Unsupported OS: $(uname -s)"
      ;;
  esac

  asset="$(pick_asset "$release_json_path" "$asset_name_pattern")" ||
    die "Could not find a matching release asset"
  IFS=$'\t' read -r asset_url asset_name <<<"$asset"
  [[ -n "$asset_url" ]] || die "Matching release asset has no API download URL"
  [[ -n "$asset_name" ]] || die "Matching release asset has no name"

  case "$(uname -s)" in
    Darwin) install_macos_dmg "$asset_url" ;;
    Linux) install_linux_pkg "$asset_url" "$asset_name" ;;
  esac
}

main "$@"
