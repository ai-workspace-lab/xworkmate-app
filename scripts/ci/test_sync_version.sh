#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
tmp_dir="$(mktemp -d "${RUNNER_TEMP:-/tmp}/xworkmate-sync-version-test.XXXXXX")"

cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

cp "$repo_root/pubspec.yaml" "$tmp_dir/pubspec.yaml"
cp "$repo_root/scripts/sync-version.sh" "$tmp_dir/sync-version.sh"

(
  cd "$tmp_dir"
  bash ./sync-version.sh --version 1.1.5+2 --commit 402da5f >/dev/null
)

if ! grep -q '^build-id: 402da5f$' "$tmp_dir/pubspec.yaml"; then
  echo "Expected build-id to be written as 402da5f" >&2
  exit 1
fi

if ! grep -q '^version: 1.1.5+2$' "$tmp_dir/pubspec.yaml"; then
  echo "Expected version to remain 1.1.5+2" >&2
  exit 1
fi

echo "sync-version.sh commit override test passed."
