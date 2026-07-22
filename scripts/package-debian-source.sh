#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app_name="xworkmate"

eval "$(python3 "$repo_root/scripts/ci/build_version.py" --format shell)"
package_version="${PLATFORM_RELEASE_VERSION}-1"

out_dir="$repo_root/dist/debian"
stage_dir="$out_dir/${app_name}-${PLATFORM_RELEASE_VERSION}"

echo "==> Preparing Debian Source Package for $app_name version $package_version..."

mkdir -p "$out_dir"
rm -rf "$stage_dir"
mkdir -p "$stage_dir"

# Copy source tree excluding build artifacts and .git
rsync -a --exclude='.git' \
         --exclude='build' \
         --exclude='dist' \
         --exclude='.dart_tool' \
         --exclude='.idea' \
         --exclude='*.log' \
         "$repo_root/" "$stage_dir/"

# Sync version in debian/changelog if necessary
changelog_path="$stage_dir/debian/changelog"
if [ -f "$changelog_path" ]; then
    cat > "$changelog_path" <<EOF
${app_name} (${package_version}) unstable; urgency=medium

  * Release version ${package_version} for Launchpad PPA and Debian packaging.

 -- AI Workspace Lab <dev@ai-workspace-lab.org>  $(date -R)
EOF
fi

echo "==> Source tree staged at $stage_dir"

if command -v dpkg-buildpackage >/dev/null 2>&1; then
    echo "==> Building Debian source package (.dsc / .changes)..."
    (cd "$stage_dir" && dpkg-buildpackage -S -us -uc)
    echo "==> Debian source package created in $out_dir:"
    ls -la "$out_dir"/*.dsc "$out_dir"/*.changes 2>/dev/null || true
    echo ""
    echo "To upload to Launchpad PPA, run:"
    echo "  dput ppa:ai-workspace-lab/ppa $out_dir/${app_name}_${package_version}_source.changes"
else
    echo "==> Creating source tarball for manual dpkg-buildpackage or Launchpad import..."
    tar_path="$out_dir/${app_name}_${PLATFORM_RELEASE_VERSION}.orig.tar.gz"
    tar -czf "$tar_path" -C "$out_dir" "${app_name}-${PLATFORM_RELEASE_VERSION}"
    echo "==> Source tarball created at $tar_path"
    echo ""
    echo "Note: 'dpkg-buildpackage' tool not found on this system."
    echo "On Ubuntu/Debian, install build tools with:"
    echo "  sudo apt-get install -y devscripts debhelper dpkg-dev"
    echo "Then run in $stage_dir:"
    echo "  dpkg-buildpackage -S -us -uc"
    echo "  dput ppa:ai-workspace-lab/ppa ../${app_name}_${package_version}_source.changes"
fi
