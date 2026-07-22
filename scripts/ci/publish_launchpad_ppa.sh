#!/usr/bin/env bash
set -euo pipefail

gpg_private_key="${1:-}"
gpg_key_id="${2:-}"
ppa_target="${3:-ppa:ai-workspace-lab/ppa}"

if [ -z "$gpg_private_key" ]; then
  echo "==> [PPA] No GPG_PRIVATE_KEY provided from Vault, skipping Launchpad PPA upload."
  exit 0
fi

echo "==> [PPA] Importing GPG private key into keychain..."
echo "$gpg_private_key" | base64 -d | gpg --batch --import 2>/dev/null || true

echo "==> [PPA] Generating Debian source package for Launchpad..."
bash scripts/package-debian-source.sh

changes_file="$(find dist/debian -name '*.changes' 2>/dev/null | head -n 1 || true)"

if [ -z "$changes_file" ]; then
  echo "==> [PPA] No .changes file generated on runner, skipping dput upload."
  exit 0
fi

if command -v debsign >/dev/null 2>&1 && [ -n "$gpg_key_id" ]; then
  echo "==> [PPA] Signing .changes file with GPG key $gpg_key_id..."
  debsign -k"$gpg_key_id" "$changes_file" || true
fi

if command -v dput >/dev/null 2>&1; then
  echo "==> [PPA] Uploading signed source package to $ppa_target..."
  dput -f "$ppa_target" "$changes_file" || {
    echo "==> [PPA] Notice: dput upload returned non-zero response (check PPA permission & key upload on Launchpad)."
    exit 0
  }
  echo "==> [PPA] Upload successfully triggered."
else
  echo "==> [PPA] Notice: 'dput' tool not installed on runner, skipping upload."
fi
