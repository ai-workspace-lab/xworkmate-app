#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app_name="xworkmate"

eval "$(python3 "$repo_root/scripts/ci/build_version.py" --format shell)"
package_version="${PLATFORM_RELEASE_VERSION}"

out_dir="$repo_root/dist/rpm"
rpm_build_dir="$out_dir/rpmbuild"
stage_dir="$out_dir/${app_name}-${package_version}"

echo "==> Preparing RPM Source Package (SRPM) for $app_name version $package_version..."

mkdir -p "$out_dir"
rm -rf "$stage_dir" "$rpm_build_dir"
mkdir -p "$stage_dir"

# Copy clean source tree
rsync -a --exclude='.git' \
         --exclude='build' \
         --exclude='dist' \
         --exclude='.dart_tool' \
         --exclude='.idea' \
         --exclude='*.log' \
         "$repo_root/" "$stage_dir/"

tar_path="$out_dir/${app_name}-${package_version}.tar.gz"
echo "==> Creating source archive $tar_path..."
tar -czf "$tar_path" -C "$out_dir" "${app_name}-${package_version}"

spec_source="$repo_root/packaging/rpm/xworkmate.spec"
spec_target="$out_dir/${app_name}.spec"
cp "$spec_source" "$spec_target"

# Sync version in spec file
sed -i.bak "s/^Version:.*/Version:        ${package_version}/" "$spec_target" && rm -f "${spec_target}.bak"

if command -v rpmbuild >/dev/null 2>&1; then
    echo "==> Building SRPM (.src.rpm) with rpmbuild..."
    mkdir -p "$rpm_build_dir/BUILD" "$rpm_build_dir/RPMS" "$rpm_build_dir/SOURCES" \
             "$rpm_build_dir/SPECS" "$rpm_build_dir/SRPMS"

    cp "$tar_path" "$rpm_build_dir/SOURCES/"
    cp "$spec_target" "$rpm_build_dir/SPECS/"

    rpmbuild --define "_topdir $rpm_build_dir" -bs "$rpm_build_dir/SPECS/${app_name}.spec"

    echo "==> SRPM created successfully in $out_dir:"
    find "$rpm_build_dir/SRPMS" -name '*.src.rpm' -exec cp {} "$out_dir/" \;
    ls -la "$out_dir"/*.src.rpm 2>/dev/null || true
    echo ""
    echo "To upload to Open Build Service (OBS) using osc:"
    echo "  osc checkout home:ai-workspace-lab/xworkmate-app"
    echo "  cp $out_dir/${app_name}-${package_version}.tar.gz $out_dir/${app_name}.spec home:ai-workspace-lab/xworkmate-app/"
    echo "  cd home:ai-workspace-lab/xworkmate-app && osc addremove && osc commit -m 'Release $package_version'"
else
    echo "==> Source tarball and Spec staged in $out_dir:"
    echo "  Tarball: $tar_path"
    echo "  Spec:    $spec_target"
    echo ""
    echo "Note: 'rpmbuild' tool not found on this system."
    echo "On Fedora/RHEL/openSUSE, install build tools with:"
    echo "  sudo dnf install -y rpm-build"
    echo "  rpmbuild -bs $spec_target --define '_sourcedir $out_dir'"
fi
