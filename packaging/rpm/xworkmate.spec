Name:           xworkmate
Version:        1.1.9
Release:        1%{?dist}
Summary:        XWorkmate Linux desktop shell with GNOME/KDE proxy and tunnel integration
License:        Apache-2.0
URL:            https://github.com/ai-workspace-lab/xworkmate-app
Source0:        xworkmate-%{version}.tar.gz

BuildRequires:  cmake
BuildRequires:  ninja-build
BuildRequires:  gcc-c++
BuildRequires:  pkgconfig
BuildRequires:  pkgconfig(gtk+-3.0)
BuildRequires:  pkgconfig(glib-2.0)

Requires:       NetworkManager
Requires:       gtk3
Requires:       glib2

%description
XWorkmate is a Linux desktop workspace shell providing workspace management,
proxy controls, and network tunnel integration across GNOME, KDE, and other desktop environments.

%prep
%autosetup -n xworkmate-%{version}

%build
# If building from source with Flutter SDK
if command -v flutter >/dev/null 2>&1; then
    flutter build linux --release
fi

%install
rm -rf %{buildroot}
mkdir -p %{buildroot}/opt/xworkmate
mkdir -p %{buildroot}/usr/bin
mkdir -p %{buildroot}/usr/share/applications
mkdir -p %{buildroot}/usr/share/icons/hicolor/scalable/apps
mkdir -p %{buildroot}/usr/share/xworkmate/autostart

if [ -d build/linux/x64/release/bundle ]; then
    cp -a build/linux/x64/release/bundle/. %{buildroot}/opt/xworkmate/
elif [ -d build/linux/arm64/release/bundle ]; then
    cp -a build/linux/arm64/release/bundle/. %{buildroot}/opt/xworkmate/
fi

ln -sf /opt/xworkmate/xworkmate %{buildroot}/usr/bin/xworkmate
cp linux/packaging/xworkmate.desktop %{buildroot}/usr/share/applications/xworkmate.desktop
cp linux/packaging/xworkmate-autostart.desktop %{buildroot}/usr/share/xworkmate/autostart/xworkmate.desktop
cp linux/packaging/icons/xworkmate.svg %{buildroot}/usr/share/icons/hicolor/scalable/apps/xworkmate.svg

%post
update-desktop-database /usr/share/applications >/dev/null 2>&1 || true
gtk-update-icon-cache -q /usr/share/icons/hicolor >/dev/null 2>&1 || true

%postun
update-desktop-database /usr/share/applications >/dev/null 2>&1 || true
gtk-update-icon-cache -q /usr/share/icons/hicolor >/dev/null 2>&1 || true

%files
/opt/xworkmate
/usr/bin/xworkmate
/usr/share/applications/xworkmate.desktop
/usr/share/icons/hicolor/scalable/apps/xworkmate.svg
/usr/share/xworkmate/autostart/xworkmate.desktop

%changelog
* Wed Jul 22 2026 AI Workspace Lab <dev@ai-workspace-lab.org> - 1.1.9-1
- Initial RPM packaging release for Open Build Service (OBS) and Fedora/openSUSE distros.
