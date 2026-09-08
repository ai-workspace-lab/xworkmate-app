#!/usr/bin/env bash
#
# Stage the installable Linux file tree ("payload") that every downstream
# Linux package embeds verbatim.
#
# Launchpad PPA builders and Open Build Service workers have no Flutter SDK and
# no network access, so they cannot compile this app themselves. Both therefore
# consume a source package that already carries the compiled bundle, and their
# packaging recipes only copy this tree into place.
#
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app_name="xworkmate"
cd "$repo_root"

eval "$(python3 "$repo_root/scripts/ci/build_version.py" --format shell)"

bundle_dir="$repo_root/build/linux/x64/release/bundle"
out_dir="$repo_root/dist/linux"
payload_dir="$out_dir/payload"
tar_path="$out_dir/${app_name}-${PLATFORM_RELEASE_VERSION}-linux-amd64.tar.gz"

if [[ ! -d "$bundle_dir" ]]; then
  echo "==> [payload] No release bundle at $bundle_dir, building it..."
  flutter build linux --release \
    --build-name="$PLATFORM_RELEASE_VERSION" \
    --build-number="$BUILD_NUMBER"
fi

if [[ ! -x "$bundle_dir/$app_name" ]]; then
  echo "==> [payload] Expected executable $bundle_dir/$app_name is missing." >&2
  exit 1
fi

echo "==> [payload] Staging install tree for $app_name $PLATFORM_RELEASE_VERSION..."
rm -rf "$payload_dir"
mkdir -p "$payload_dir/opt/$app_name" \
         "$payload_dir/usr/share/applications" \
         "$payload_dir/usr/share/icons/hicolor/scalable/apps" \
         "$payload_dir/usr/share/$app_name/autostart"

cp -R "$bundle_dir/." "$payload_dir/opt/$app_name/"
cp "$repo_root/linux/packaging/xworkmate.desktop" \
  "$payload_dir/usr/share/applications/$app_name.desktop"
cp "$repo_root/linux/packaging/xworkmate-autostart.desktop" \
  "$payload_dir/usr/share/$app_name/autostart/$app_name.desktop"
cp "$repo_root/linux/packaging/icons/xworkmate.svg" \
  "$payload_dir/usr/share/icons/hicolor/scalable/apps/$app_name.svg"

chmod 0755 "$payload_dir/opt/$app_name/$app_name"

rm -f "$tar_path"
tar -czf "$tar_path" -C "$out_dir" payload

echo "==> [payload] Staged at $payload_dir"
echo "==> [payload] Archived at $tar_path"
