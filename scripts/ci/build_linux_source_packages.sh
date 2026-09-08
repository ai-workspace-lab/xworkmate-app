#!/usr/bin/env bash
#
# Produce and sanity-check everything the Launchpad PPA and Open Build Service
# lanes upload later: one Debian source package per Ubuntu series, plus the OBS
# tarball/spec/rpmlintrc set.
#
# This runs on every build, including pull requests, so a packaging regression
# fails here rather than three jobs later against a live archive.
#
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
app_name="xworkmate"
cd "$repo_root"

bash ./scripts/package-linux-payload.sh
bash ./scripts/package-debian-source.sh
bash ./scripts/package-rpm-source.sh

# The version scheme is load-bearing: an untagged CI build must never outrank
# the tagged release of the same upstream version, and each Ubuntu series must
# sort above the previous one so release upgrades keep moving forward.
echo "==> [verify] Checking the Debian version ordering invariants..."
eval "$(python3 ./scripts/ci/build_version.py --format shell)"
base_version="$PLATFORM_RELEASE_VERSION"
ci_version="${base_version}~ci${GITHUB_RUN_NUMBER:-${BUILD_NUMBER}}~ubuntu22.04.1"
tag_version="${base_version}~ubuntu22.04.1"
next_series_version="${base_version}~ubuntu24.04.1"

if ! dpkg --compare-versions "$ci_version" lt "$tag_version"; then
  echo "==> [verify] $ci_version does not sort below $tag_version." >&2
  exit 1
fi
if ! dpkg --compare-versions "$tag_version" lt "$next_series_version"; then
  echo "==> [verify] $tag_version does not sort below $next_series_version." >&2
  exit 1
fi
echo "==> [verify] $ci_version < $tag_version < $next_series_version"

echo "==> [verify] Checking the generated Debian source packages..."
verify_root="$(mktemp -d)"
trap 'rm -rf "$verify_root"' EXIT

mapfile -t dsc_files < <(find "$repo_root/dist/ppa" -mindepth 1 -maxdepth 2 -name '*.dsc' | sort)
if [[ "${#dsc_files[@]}" -eq 0 ]]; then
  echo "==> [verify] No .dsc files were produced." >&2
  exit 1
fi

for dsc in "${dsc_files[@]}"; do
  name="$(basename "$dsc" .dsc)"
  extract_dir="$verify_root/$name"
  dpkg-source --no-check -x "$dsc" "$extract_dir" >/dev/null

  if [[ ! -x "$extract_dir/payload/opt/$app_name/$app_name" ]]; then
    echo "==> [verify] $name unpacks without payload/opt/$app_name/$app_name." >&2
    exit 1
  fi
  if [[ ! -x "$extract_dir/debian/rules" ]]; then
    echo "==> [verify] $name unpacks without an executable debian/rules." >&2
    exit 1
  fi

  changes_file="${dsc%.dsc}_source.changes"
  distribution="$(awk '/^Distribution:/ {print $2; exit}' "$changes_file")"
  if [[ -z "$distribution" || "$distribution" == "unstable" || "$distribution" == "UNRELEASED" ]]; then
    echo "==> [verify] $name targets '$distribution'; Launchpad only accepts an Ubuntu series." >&2
    exit 1
  fi

  echo "==> [verify] $name -> $distribution: payload and packaging present."

  # Advisory only: lintian flags a vendor bundle under /opt in ways that are
  # inherent to shipping prebuilt Flutter output, so its findings are printed
  # for review rather than gating the build.
  if command -v lintian >/dev/null 2>&1; then
    lintian --no-tag-display-limit "$dsc" || true
  fi
done

echo "==> [verify] Checking the OBS upload set..."
obs_tarball="$(find "$repo_root/dist/obs" -maxdepth 1 -name '*.tar.gz' | sort | head -n 1)"
if [[ -z "$obs_tarball" || ! -f "$repo_root/dist/obs/${app_name}.spec" ]]; then
  echo "==> [verify] dist/obs is missing a tarball or ${app_name}.spec." >&2
  exit 1
fi
if ! tar -tzf "$obs_tarball" | grep -q "payload/opt/${app_name}/${app_name}$"; then
  echo "==> [verify] $obs_tarball does not contain payload/opt/${app_name}/${app_name}." >&2
  exit 1
fi
echo "==> [verify] $(basename "$obs_tarball"): payload present."

echo "==> [verify] Linux source packages are ready to publish."
