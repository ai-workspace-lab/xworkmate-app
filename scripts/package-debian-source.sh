#!/usr/bin/env bash
#
# Build signed-ready Debian source packages (.dsc / .tar.xz / _source.changes)
# for every target Ubuntu series, ready for `dput` to a Launchpad PPA.
#
# Launchpad builds each series separately and refuses to accept a version it has
# already seen, so one source package is produced per series with a distinct,
# monotonically increasing version.
#
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app_name="xworkmate"
cd "$repo_root"

payload_dir="${PAYLOAD_DIR:-$repo_root/dist/linux/payload}"
out_root="${DEB_SOURCE_OUT_DIR:-$repo_root/dist/ppa}"
# "<series>:<ubuntu version>" pairs. The Ubuntu version becomes the version
# suffix so the same upstream release can be uploaded to several series.
series_spec="${PPA_SERIES:-jammy:22.04 noble:24.04}"
package_revision="${PPA_PACKAGE_REVISION:-1}"
maintainer="${DEB_MAINTAINER:-AI Workspace Lab <dev@ai-workspace-lab.org>}"

eval "$(python3 "$repo_root/scripts/ci/build_version.py" --format shell)"

# Untagged builds must sort below the eventual tagged release of the same
# upstream version, hence the leading "~" on the CI marker.
if [[ "${GITHUB_REF_TYPE:-}" == "tag" ]]; then
  ci_marker=""
else
  ci_marker="~ci${GITHUB_RUN_NUMBER:-${BUILD_NUMBER}}"
fi

if [[ ! -x "$payload_dir/opt/$app_name/$app_name" ]]; then
  echo "==> [deb-source] Payload missing at $payload_dir." >&2
  echo "                 Run scripts/package-linux-payload.sh first." >&2
  exit 1
fi

if ! command -v dpkg-buildpackage >/dev/null 2>&1; then
  echo "==> [deb-source] dpkg-buildpackage not found." >&2
  echo "                 On Ubuntu/Debian: sudo apt-get install -y dpkg-dev debhelper devscripts" >&2
  exit 1
fi

rm -rf "$out_root"
mkdir -p "$out_root"

for entry in $series_spec; do
  series="${entry%%:*}"
  series_version="${entry##*:}"
  if [[ -z "$series" || -z "$series_version" || "$series" == "$series_version" ]]; then
    echo "==> [deb-source] Malformed PPA_SERIES entry: '$entry' (expected '<series>:<version>')." >&2
    exit 1
  fi

  deb_version="${PLATFORM_RELEASE_VERSION}${ci_marker}~ubuntu${series_version}.${package_revision}"
  series_dir="$out_root/$series"
  stage_dir="$series_dir/${app_name}-${deb_version}"

  echo "==> [deb-source] Staging ${app_name} ${deb_version} for ${series}..."
  mkdir -p "$stage_dir"
  cp -R "$repo_root/debian" "$stage_dir/debian"
  cp "$repo_root/LICENSE" "$stage_dir/LICENSE"
  cp "$repo_root/README.md" "$stage_dir/README.md"

  # The payload ships as one archive rather than a loose tree: dpkg-source
  # applies default tar-ignore patterns when it builds the source tarball, and
  # those cover *.so, *.a and *.o -- which is most of a Flutter bundle,
  # including libapp.so and the engine. A loose tree loses them silently.
  tar -czf "$stage_dir/payload.tar.gz" -C "$payload_dir" .

  cat > "$stage_dir/SOURCE.md" <<EOF
# XWorkmate source package contents

This package installs a prebuilt XWorkmate release bundle. Distribution build
chroots have no Flutter SDK and no network access, so the compiled bundle is
shipped as \`payload.tar.gz\` and \`debian/rules\` only unpacks it into place.
It is an archive rather than a loose tree because dpkg-source's default
tar-ignore patterns would drop the bundle's shared libraries.

The complete application source, along with the packaging scripts that produced
this archive, lives at:

  https://github.com/ai-workspace-lab/xworkmate-app

Upstream version: ${DISPLAY_VERSION} (build ${BUILD_NUMBER})
EOF

  cat > "$stage_dir/debian/changelog" <<EOF
${app_name} (${deb_version}) ${series}; urgency=medium

  * Automated build of XWorkmate ${DISPLAY_VERSION} (build ${BUILD_NUMBER}).

 -- ${maintainer}  $(date -R)
EOF

  echo "==> [deb-source] Building source package for ${series}..."
  (cd "$stage_dir" && dpkg-buildpackage -S -us -uc -d)

  changes_file="$series_dir/${app_name}_${deb_version}_source.changes"
  if [[ ! -f "$changes_file" ]]; then
    echo "==> [deb-source] Expected $changes_file was not produced." >&2
    exit 1
  fi

  rm -rf "$stage_dir"
  echo "==> [deb-source] ${series}: $changes_file"
done

echo "==> [deb-source] Source packages under $out_root:"
find "$out_root" -maxdepth 2 -type f \( -name '*.dsc' -o -name '*.changes' -o -name '*.tar.xz' \) -print
