#!/usr/bin/env bash
#
# Exercise the Launchpad signing path against a throwaway key.
#
# Everything up to `dput` -- importing a base64 secret key, resolving its
# fingerprint, signing each .changes with debsign, and verifying the result --
# runs here on a copy of the built source packages. Without this the signing
# code would only ever run against the live archive with the real key.
#
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

source_dir="${PPA_SOURCE_DIR:-$repo_root/dist/ppa}"

if [[ ! -d "$source_dir" ]]; then
  echo "==> [ppa-signing] $source_dir does not exist." >&2
  echo "                  Run scripts/ci/build_linux_source_packages.sh first." >&2
  exit 1
fi

work_dir="$(mktemp -d)"
export GNUPGHOME="$work_dir/gnupg"
mkdir -p "$GNUPGHOME"
chmod 700 "$GNUPGHOME"
cleanup() {
  gpgconf --kill gpg-agent >/dev/null 2>&1 || true
  rm -rf "$work_dir"
}
trap cleanup EXIT

echo "==> [ppa-signing] Generating a throwaway signing key..."
gpg --batch --quick-generate-key \
  "XWorkmate CI Signing Check <ci@example.invalid>" ed25519 sign never >/dev/null 2>&1

key_id="$(gpg --list-secret-keys --with-colons | awk -F: '/^sec:/ {print $5}' | sed -n '1p')"
if [[ -z "$key_id" ]]; then
  echo "==> [ppa-signing] Failed to generate a throwaway key." >&2
  exit 1
fi

private_key="$(gpg --export-secret-keys --armor "$key_id" | base64 -w0)"

# Sign a copy so the artefacts that ship to the release job stay unsigned, ready
# for the real key.
staging_dir="$work_dir/ppa"
cp -R "$source_dir" "$staging_dir"

echo "==> [ppa-signing] Running the publisher in dry-run mode..."
env -u GNUPGHOME \
  PPA_SOURCE_DIR="$staging_dir" \
  PPA_DRY_RUN=true \
  bash ./scripts/ci/publish_launchpad_ppa.sh "$private_key" "$key_id"

echo "==> [ppa-signing] Signing path verified."
