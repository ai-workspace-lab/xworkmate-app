#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app_name="xworkmate"

eval "$(python3 "$repo_root/scripts/ci/build_version.py" --format shell)"
package_version="${PLATFORM_RELEASE_VERSION}-${BUILD_NUMBER}"

build_dir="$repo_root/build/linux/x64/release/bundle"
stage_dir="$repo_root/build/linux/deb-stage"
out_dir="$repo_root/dist/linux"

cd "$repo_root"
flutter build linux --release

rm -rf "$stage_dir"
mkdir -p "$stage_dir/DEBIAN"
mkdir -p "$stage_dir/opt/$app_name"
mkdir -p "$stage_dir/usr/share/applications"
mkdir -p "$stage_dir/usr/share/icons/hicolor/scalable/apps"
mkdir -p "$stage_dir/usr/share/$app_name/autostart"

cp -R "$build_dir/." "$stage_dir/opt/$app_name/"
cp "$repo_root/linux/packaging/xworkmate.desktop" \
  "$stage_dir/usr/share/applications/$app_name.desktop"
cp "$repo_root/linux/packaging/xworkmate-autostart.desktop" \
  "$stage_dir/usr/share/$app_name/autostart/$app_name.desktop"
cp "$repo_root/linux/packaging/icons/xworkmate.svg" \
  "$stage_dir/usr/share/icons/hicolor/scalable/apps/$app_name.svg"
cp "$repo_root/scripts/linux-postinst.sh" "$stage_dir/DEBIAN/postinst"
cp "$repo_root/scripts/linux-postrm.sh" "$stage_dir/DEBIAN/postrm"
chmod 0755 "$stage_dir/DEBIAN/postinst" "$stage_dir/DEBIAN/postrm"

cat > "$stage_dir/DEBIAN/control" <<EOF
Package: $app_name
Version: $package_version
Section: utils
Priority: optional
Architecture: amd64
Maintainer: XWorkmate
Depends: network-manager, libgtk-3-0
Description: XWorkmate Linux desktop shell with GNOME/KDE proxy and tunnel integration
EOF

mkdir -p "$out_dir"
dpkg-deb --build "$stage_dir" "$out_dir/${app_name}_${package_version}_amd64.deb"
