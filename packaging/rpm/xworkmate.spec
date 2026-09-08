# XWorkmate ships to Open Build Service as a prebuilt payload: OBS workers have
# neither the Flutter SDK nor network access, so the source tarball carries the
# compiled bundle under payload/ and this spec only installs it. Regenerate the
# tarball with scripts/package-rpm-source.sh.

# The payload is already-linked upstream output. Let RPM copy it verbatim
# instead of stripping it, extracting debuginfo, or deriving dependencies from
# the private sonames it bundles.
%global debug_package %{nil}
%global __os_install_post %{nil}
%global _build_id_links none

Name:           xworkmate
Version:        1.1.9
Release:        1%{?dist}
Summary:        XWorkmate Linux desktop shell with GNOME/KDE proxy and tunnel integration
License:        Apache-2.0
URL:            https://github.com/ai-workspace-lab/xworkmate-app
Source0:        %{name}-%{version}.tar.gz
Source1:        %{name}-rpmlintrc

ExclusiveArch:  x86_64
AutoReqProv:    no

Requires:       libgtk-3.so.0()(64bit)
Requires:       libgdk-3.so.0()(64bit)
Requires:       libglib-2.0.so.0()(64bit)
Requires:       libgobject-2.0.so.0()(64bit)
Requires:       libgio-2.0.so.0()(64bit)
Requires:       libX11.so.6()(64bit)
Requires:       libstdc++.so.6()(64bit)
Requires:       NetworkManager

%description
XWorkmate is a Linux desktop workspace shell providing workspace management,
proxy controls, and network tunnel integration across GNOME, KDE, and other
desktop environments.

%prep
%autosetup -n %{name}-%{version}

%build
# Nothing to compile: payload/ already contains the release bundle.
test -x payload/opt/%{name}/%{name} || {
    echo "ERROR: payload/opt/%{name}/%{name} is missing from the source tarball." >&2
    exit 1
}

%install
rm -rf %{buildroot}
mkdir -p %{buildroot}
cp -a payload/. %{buildroot}/
mkdir -p %{buildroot}%{_bindir}
ln -sf /opt/%{name}/%{name} %{buildroot}%{_bindir}/%{name}

%post
update-desktop-database %{_datadir}/applications >/dev/null 2>&1 || :
gtk-update-icon-cache -q %{_datadir}/icons/hicolor >/dev/null 2>&1 || :

%postun
update-desktop-database %{_datadir}/applications >/dev/null 2>&1 || :
gtk-update-icon-cache -q %{_datadir}/icons/hicolor >/dev/null 2>&1 || :

%files
/opt/%{name}
%{_bindir}/%{name}
%{_datadir}/applications/%{name}.desktop
%{_datadir}/icons/hicolor/scalable/apps/%{name}.svg
%{_datadir}/%{name}

%changelog
* Tue Sep 08 2026 AI Workspace Lab <dev@ai-workspace-lab.org> - 1.1.9-1
- Install the prebuilt Linux bundle so OBS workers no longer need the Flutter SDK.
* Wed Jul 22 2026 AI Workspace Lab <dev@ai-workspace-lab.org> - 1.1.9-1
- Initial RPM packaging release for Open Build Service (OBS) and Fedora/openSUSE distros.
