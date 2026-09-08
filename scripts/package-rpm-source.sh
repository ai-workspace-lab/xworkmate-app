#!/usr/bin/env bash
#
# Stage the RPM source bundle (tarball + spec + rpmlintrc) that gets committed
# to Open Build Service, and build a local SRPM when rpmbuild is available.
#
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app_name="xworkmate"
cd "$repo_root"

payload_dir="${PAYLOAD_DIR:-$repo_root/dist/linux/payload}"
out_dir="${RPM_SOURCE_OUT_DIR:-$repo_root/dist/obs}"
rpm_build_dir="$out_dir/rpmbuild"

eval "$(python3 "$repo_root/scripts/ci/build_version.py" --format shell)"
package_version="${PLATFORM_RELEASE_VERSION}"

# Untagged builds sort below the eventual tagged release: rpm compares release
# segment by segment, so "0.ci42" precedes "1".
if [[ "${GITHUB_REF_TYPE:-}" == "tag" ]]; then
  package_release="1"
else
  package_release="0.ci${GITHUB_RUN_NUMBER:-${BUILD_NUMBER}}"
fi

if [[ ! -x "$payload_dir/opt/$app_name/$app_name" ]]; then
  echo "==> [rpm-source] Payload missing at $payload_dir." >&2
  echo "                 Run scripts/package-linux-payload.sh first." >&2
  exit 1
fi

echo "==> [rpm-source] Staging ${app_name} ${package_version}-${package_release}..."
rm -rf "$out_dir"
stage_dir="$out_dir/${app_name}-${package_version}"
mkdir -p "$stage_dir"

cp -R "$payload_dir" "$stage_dir/payload"
cp "$repo_root/LICENSE" "$stage_dir/LICENSE"
cp "$repo_root/README.md" "$stage_dir/README.md"

tar_path="$out_dir/${app_name}-${package_version}.tar.gz"
tar -czf "$tar_path" -C "$out_dir" "${app_name}-${package_version}"
rm -rf "$stage_dir"

spec_target="$out_dir/${app_name}.spec"
cp "$repo_root/packaging/rpm/${app_name}.spec" "$spec_target"
cp "$repo_root/packaging/rpm/${app_name}-rpmlintrc" "$out_dir/${app_name}-rpmlintrc"

python3 - "$spec_target" "$package_version" "$package_release" <<'PY'
import pathlib
import re
import sys

spec_path, version, release = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
text = spec_path.read_text(encoding="utf-8")
text, version_hits = re.subn(r"^Version:.*$", f"Version:        {version}", text, count=1, flags=re.MULTILINE)
text, release_hits = re.subn(r"^Release:.*$", f"Release:        {release}%{{?dist}}", text, count=1, flags=re.MULTILINE)
if not version_hits or not release_hits:
    raise SystemExit(f"Failed to sync Version/Release in {spec_path}")
spec_path.write_text(text, encoding="utf-8")
PY

if command -v rpmbuild >/dev/null 2>&1; then
  echo "==> [rpm-source] Building SRPM..."
  mkdir -p "$rpm_build_dir"/{BUILD,RPMS,SOURCES,SPECS,SRPMS}
  cp "$tar_path" "$out_dir/${app_name}-rpmlintrc" "$rpm_build_dir/SOURCES/"
  cp "$spec_target" "$rpm_build_dir/SPECS/"
  rpmbuild --define "_topdir $rpm_build_dir" -bs "$rpm_build_dir/SPECS/${app_name}.spec"
  find "$rpm_build_dir/SRPMS" -name '*.src.rpm' -exec cp {} "$out_dir/" \;
  rm -rf "$rpm_build_dir"
else
  echo "==> [rpm-source] rpmbuild not found; skipping local SRPM build."
  echo "                 OBS rebuilds from the tarball and spec, so this is optional."
fi

echo "==> [rpm-source] OBS upload set staged in $out_dir:"
find "$out_dir" -maxdepth 1 -type f -print
