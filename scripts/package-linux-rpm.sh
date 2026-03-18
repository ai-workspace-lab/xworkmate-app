#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app_name="xworkmate"
version="$(python3 - <<'PY'
from pathlib import Path
import re
text = Path("pubspec.yaml").read_text()
match = re.search(r"^version:\s*([^\n+]+)", text, re.M)
print(match.group(1) if match else "0.0.0")
PY
)"

bundle_dir="$repo_root/build/linux/x64/release/bundle"
rpm_root="$repo_root/build/linux/rpm"
spec_file="$rpm_root/SPECS/${app_name}.spec"
out_dir="$repo_root/dist/linux"

cd "$repo_root"
flutter build linux --release

rm -rf "$rpm_root"
mkdir -p "$rpm_root/BUILD" "$rpm_root/RPMS" "$rpm_root/SOURCES" \
  "$rpm_root/SPECS" "$rpm_root/SRPMS"

cp -R "$bundle_dir" "$rpm_root/SOURCES/bundle"
cp "$repo_root/linux/packaging/xworkmate.desktop" \
  "$rpm_root/SOURCES/$app_name.desktop"
cp "$repo_root/linux/packaging/xworkmate-autostart.desktop" \
  "$rpm_root/SOURCES/$app_name-autostart.desktop"
cp "$repo_root/linux/packaging/icons/xworkmate.svg" \
  "$rpm_root/SOURCES/$app_name.svg"

cat > "$spec_file" <<EOF
Name: $app_name
Version: $version
Release: 1%{?dist}
Summary: XWorkmate Linux desktop shell
License: Proprietary
BuildArch: x86_64
Requires: NetworkManager, gtk3

%description
XWorkmate Linux desktop shell with GNOME/KDE proxy and tunnel integration.

%install
mkdir -p %{buildroot}/opt/$app_name
mkdir -p %{buildroot}/usr/share/applications
mkdir -p %{buildroot}/usr/share/icons/hicolor/scalable/apps
mkdir -p %{buildroot}/usr/share/$app_name/autostart
cp -a %{_sourcedir}/bundle/. %{buildroot}/opt/$app_name/
cp %{_sourcedir}/$app_name.desktop %{buildroot}/usr/share/applications/$app_name.desktop
cp %{_sourcedir}/$app_name-autostart.desktop %{buildroot}/usr/share/$app_name/autostart/$app_name.desktop
cp %{_sourcedir}/$app_name.svg %{buildroot}/usr/share/icons/hicolor/scalable/apps/$app_name.svg

%post
update-desktop-database /usr/share/applications >/dev/null 2>&1 || true
gtk-update-icon-cache -q /usr/share/icons/hicolor >/dev/null 2>&1 || true

%postun
update-desktop-database /usr/share/applications >/dev/null 2>&1 || true
gtk-update-icon-cache -q /usr/share/icons/hicolor >/dev/null 2>&1 || true

%files
/opt/$app_name
/usr/share/applications/$app_name.desktop
/usr/share/icons/hicolor/scalable/apps/$app_name.svg
/usr/share/$app_name/autostart/$app_name.desktop
EOF

mkdir -p "$out_dir"
rpmbuild --define "_topdir $rpm_root" --define "__spec_install_post %{nil}" \
  -bb "$spec_file"
find "$rpm_root/RPMS" -name '*.rpm' -exec cp {} "$out_dir/" \;
