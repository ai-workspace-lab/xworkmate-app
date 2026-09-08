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

payload_dir="${PAYLOAD_DIR:-$repo_root/dist/linux/payload}"

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

  if [[ ! -f "$extract_dir/payload.tar.gz" ]]; then
    echo "==> [verify] $name unpacks without payload.tar.gz." >&2
    exit 1
  fi

  # dpkg-source applies default tar-ignore patterns when it builds the source
  # tarball, and those cover exactly what a prebuilt Flutter bundle is made of
  # (*.so, *.a, *.o) -- libapp.so and the engine included. The payload therefore
  # ships as one archive, and this compares the round trip file by file so a
  # silently dropped library cannot reach an archive.
  (cd "$payload_dir" && find . \( -type f -o -type l \) | sort) > "$verify_root/staged.list"
  # awk rather than `grep -v`: an empty result would exit non-zero and abort
  # under `set -e` with no explanation, instead of reporting the real diff.
  tar -tzf "$extract_dir/payload.tar.gz" | awk '!/\/$/' | sort > "$verify_root/unpacked.list"
  if ! diff -u "$verify_root/staged.list" "$verify_root/unpacked.list" > "$verify_root/payload.diff"; then
    echo "==> [verify] $name does not round-trip the staged payload:" >&2
    head -n 40 "$verify_root/payload.diff" >&2
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

# The closest available stand-in for a Launchpad build: unpack the source
# package and run the same debhelper sequence a builder would, with the same
# build-dependency check. Anything the packaging gets wrong about dh surfaces
# here instead of in the archive.
first_dsc="${dsc_files[0]}"
first_extract="$verify_root/$(basename "$first_dsc" .dsc)"
echo "==> [verify] Building a binary package from $(basename "$first_dsc")..."
(cd "$first_extract" && dpkg-buildpackage -b -us -uc)

mapfile -t built_debs < <(find "$verify_root" -maxdepth 1 -name '*.deb' | sort)
if [[ "${#built_debs[@]}" -eq 0 ]]; then
  echo "==> [verify] The source package did not produce a .deb." >&2
  exit 1
fi

deb_listing="$verify_root/deb-contents.list"
dpkg-deb -c "${built_debs[0]}" > "$deb_listing"
# dpkg-deb prints paths as "./opt/...", and symlinks as "./usr/bin/x -> target",
# so anchor on the leading "./" -- matching the bare path would let the symlink's
# target stand in for the binary it points at.
deb_required=(
  "\./opt/${app_name}/${app_name}\$"
  "\./usr/bin/${app_name} ->"
  "\./usr/share/applications/${app_name}\.desktop\$"
  "\./usr/share/icons/hicolor/scalable/apps/${app_name}\.svg\$"
)
for required in "${deb_required[@]}"; do
  if ! grep -q "$required" "$deb_listing"; then
    echo "==> [verify] $(basename "${built_debs[0]}") has nothing matching '$required'." >&2
    exit 1
  fi
done
echo "==> [verify] $(basename "${built_debs[0]}") installs the payload."

echo "==> [verify] Checking the OBS upload set..."
# Read pipelines fully rather than piping into an early-exiting reader: under
# `set -o pipefail` the writer's SIGPIPE would surface as a failed check.
mapfile -t obs_tarballs < <(find "$repo_root/dist/obs" -maxdepth 1 -name '*.tar.gz' | sort)
obs_tarball="${obs_tarballs[0]:-}"
if [[ -z "$obs_tarball" || ! -f "$repo_root/dist/obs/${app_name}.spec" ]]; then
  echo "==> [verify] dist/obs is missing a tarball or ${app_name}.spec." >&2
  exit 1
fi
obs_listing="$verify_root/obs-tarball.list"
tar -tzf "$obs_tarball" > "$obs_listing"
if ! grep -q "payload/opt/${app_name}/${app_name}\$" "$obs_listing"; then
  echo "==> [verify] $obs_tarball does not contain payload/opt/${app_name}/${app_name}." >&2
  exit 1
fi
echo "==> [verify] $(basename "$obs_tarball"): payload present."

# The OBS analogue of the binary build above: OBS rebuilds from this tarball and
# spec, so run rpmbuild here and confirm the package it produces carries the
# payload rather than an empty tree.
if command -v rpmbuild >/dev/null 2>&1; then
  echo "==> [verify] Building a binary RPM from $(basename "$obs_tarball")..."
  rpm_root="$verify_root/rpmbuild"
  mkdir -p "$rpm_root"/{BUILD,RPMS,SOURCES,SPECS,SRPMS}
  cp "$obs_tarball" "$rpm_root/SOURCES/"
  cp "$repo_root/dist/obs/${app_name}-rpmlintrc" "$rpm_root/SOURCES/"
  cp "$repo_root/dist/obs/${app_name}.spec" "$rpm_root/SPECS/"
  rpmbuild --define "_topdir $rpm_root" -bb "$rpm_root/SPECS/${app_name}.spec"

  mapfile -t built_rpms < <(find "$rpm_root/RPMS" -name '*.rpm' | sort)
  if [[ "${#built_rpms[@]}" -eq 0 ]]; then
    echo "==> [verify] The spec did not produce an RPM." >&2
    exit 1
  fi

  rpm_listing="$verify_root/rpm-contents.list"
  rpm -qlp "${built_rpms[0]}" > "$rpm_listing"
  rpm_required=(
    "^/opt/${app_name}/${app_name}\$"
    "^/usr/bin/${app_name}\$"
    "^/usr/share/applications/${app_name}\.desktop\$"
    "^/usr/share/icons/hicolor/scalable/apps/${app_name}\.svg\$"
  )
  for required in "${rpm_required[@]}"; do
    if ! grep -q "$required" "$rpm_listing"; then
      echo "==> [verify] $(basename "${built_rpms[0]}") has nothing matching '$required'." >&2
      exit 1
    fi
  done
  echo "==> [verify] $(basename "${built_rpms[0]}") installs the payload."
else
  echo "==> [verify] rpmbuild unavailable; skipping the RPM build check."
fi

echo "==> [verify] Linux source packages are ready to publish."
