#!/usr/bin/env bash
#
# Sign the prebuilt Debian source packages and upload them to a Launchpad PPA.
#
# The source packages themselves are produced earlier (scripts/package-debian-source.sh)
# so that the signing key only ever touches a machine that already has the
# finished artefacts.
#
set -euo pipefail

gpg_private_key="${1:-${GPG_PRIVATE_KEY:-}}"
gpg_key_id="${2:-${GPG_KEY_ID:-}}"
ppa_target="${3:-${PPA_TARGET:-ppa:ai-workspace-lab/ppa}}"

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

source_dir="${PPA_SOURCE_DIR:-$repo_root/dist/ppa}"
# When publishing is explicitly requested, missing credentials are a failure:
# silently uploading nothing is how a release lane rots unnoticed.
require_upload="${PPA_REQUIRE_UPLOAD:-true}"

fail_or_skip() {
  local message="$1"
  if [[ "$require_upload" == "true" ]]; then
    echo "==> [PPA] $message" >&2
    exit 1
  fi
  echo "==> [PPA] $message Skipping (PPA_REQUIRE_UPLOAD=false)."
  exit 0
}

if [[ -z "$gpg_private_key" ]]; then
  fail_or_skip "No GPG private key available; cannot sign a Launchpad upload."
fi

if [[ -z "$gpg_key_id" ]]; then
  fail_or_skip "No GPG key id available; cannot select a signing key."
fi

for tool in gpg debsign dput; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "==> [PPA] Required tool '$tool' is not installed." >&2
    echo "          On Ubuntu: sudo apt-get install -y gnupg devscripts dput" >&2
    exit 1
  fi
done

mapfile -t changes_files < <(find "$source_dir" -mindepth 1 -maxdepth 2 -name '*_source.changes' | sort)
if [[ "${#changes_files[@]}" -eq 0 ]]; then
  echo "==> [PPA] No *_source.changes found under $source_dir." >&2
  echo "          Run scripts/package-debian-source.sh (or download the build artefact) first." >&2
  exit 1
fi

gnupg_home="$(mktemp -d)"
chmod 700 "$gnupg_home"
export GNUPGHOME="$gnupg_home"
cleanup() {
  gpgconf --kill gpg-agent >/dev/null 2>&1 || true
  rm -rf "$gnupg_home"
}
trap cleanup EXIT

{
  echo "batch"
  echo "pinentry-mode loopback"
} > "$gnupg_home/gpg.conf"
echo "allow-loopback-pinentry" > "$gnupg_home/gpg-agent.conf"

if [[ -n "${GPG_PASSPHRASE:-}" ]]; then
  printf '%s' "$GPG_PASSPHRASE" > "$gnupg_home/passphrase"
  chmod 600 "$gnupg_home/passphrase"
  echo "passphrase-file $gnupg_home/passphrase" >> "$gnupg_home/gpg.conf"
fi

echo "==> [PPA] Importing signing key..."
if ! printf '%s' "$gpg_private_key" | base64 -d 2>/dev/null | gpg --import 2>&1; then
  echo "==> [PPA] Failed to import the GPG private key." >&2
  echo "          It must be a base64-encoded, ASCII-armored secret key export." >&2
  exit 1
fi

# No stage exits early here: an `exit` in awk would SIGPIPE gpg, which under
# `set -o pipefail` reads as "no such key".
fingerprint="$(gpg --list-secret-keys --with-colons "$gpg_key_id" 2>/dev/null | awk -F: '/^fpr:/ {print $10}' | sed -n '1p')"
if [[ -z "$fingerprint" ]]; then
  echo "==> [PPA] Imported keyring has no secret key matching '$gpg_key_id'." >&2
  gpg --list-secret-keys --keyid-format LONG >&2 || true
  exit 1
fi
echo "$fingerprint:6:" | gpg --import-ownertrust >/dev/null 2>&1

echo "==> [PPA] Signing and uploading ${#changes_files[@]} source package(s) to $ppa_target..."
for changes_file in "${changes_files[@]}"; do
  distribution="$(awk '/^Distribution:/ {print $2; exit}' "$changes_file")"
  echo "==> [PPA] ${distribution:-unknown}: $(basename "$changes_file")"

  debsign -k"$fingerprint" "$changes_file"
  gpg --verify "$changes_file" >/dev/null 2>&1 || {
    echo "==> [PPA] Signature verification failed for $changes_file." >&2
    exit 1
  }

  dput --force "$ppa_target" "$changes_file"
done

echo "==> [PPA] Uploaded ${#changes_files[@]} source package(s) to $ppa_target."
ppa_path="${ppa_target#ppa:}"
echo "==> [PPA] Track the builds at https://launchpad.net/~${ppa_path%%/*}/+archive/ubuntu/${ppa_path#*/}"
