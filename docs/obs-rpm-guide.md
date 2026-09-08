# Open Build Service (OBS) & RPM Packaging Guide

How **XWorkmate** (`xworkmate`) is packaged and published to
[build.opensuse.org](https://build.opensuse.org) for openSUSE, Fedora, and
RHEL/CentOS.

---

## 1. Why the tarball ships a prebuilt bundle

OBS workers build in a clean chroot with **no Flutter SDK and no network
access**, exactly like Launchpad. The source tarball therefore carries the
compiled release bundle under `payload/`, and `packaging/rpm/xworkmate.spec`
only installs it — `%build` does nothing but assert the payload is present.

That shapes the spec:

* `%global __os_install_post %{nil}` and `%global debug_package %{nil}` stop RPM
  from stripping the vendored binaries or trying to extract debuginfo from them.
* `AutoReqProv: no` with explicit soname requirements
  (`libgtk-3.so.0()(64bit)`, …) keeps dependency resolution portable across
  openSUSE and Fedora, whose package names differ, and stops RPM from requiring
  the bundle's own private sonames.
* `ExclusiveArch: x86_64` — the payload is an x86-64 build.
* `packaging/rpm/xworkmate-rpmlintrc` is uploaded alongside the spec. OBS treats
  some rpmlint findings as fatal, and a vendor bundle under `/opt` trips several
  that are inherent to shipping prebuilt output.

---

## 2. Infrastructure

| Property | Value |
| :--- | :--- |
| API endpoint | `https://api.opensuse.org` |
| Project | `home:haitaopanhq` (override with the `obs-project` action input) |
| Package | `xworkmate` |
| RPM package name | `xworkmate` |

One-time setup: create the project on OBS and add the build targets you want
(openSUSE Tumbleweed / Leap, Fedora, RHEL). The publishing script creates the
*package* inside the project automatically if it does not exist yet; it does not
create the project or choose its repositories.

---

## 3. Two publishing modes

`scripts/ci/publish_obs_package.sh` picks a mode from the credentials it is
given:

| Mode | Credentials | What it does |
| :--- | :--- | :--- |
| **osc** (preferred) | `OBS_USERNAME` + `OBS_PASSWORD` | Checks out the package, replaces the tarball / spec / rpmlintrc, and commits. This is what actually ships a new version. |
| **token** (fallback) | `OBS_TOKEN` | `POST /trigger/runservice`, which only re-runs source services **already configured** on the OBS package. It cannot upload new sources. |

A token alone is therefore not enough to publish a build produced in CI unless
the OBS package has a `_service` that fetches the sources itself. Provision
`OBS_USERNAME` and `OBS_PASSWORD` in Vault to use the osc mode — see the
[GPG Key & Vault Setup Guide](gpg-key-vault-setup-guide.md) for the secret path.

Either way, failures are reported: an HTTP error from the trigger endpoint fails
the job instead of being swallowed.

---

## 4. Versioning

| Build | Version-Release |
| :--- | :--- |
| Tagged release | `1.2.0-1` |
| Untagged CI build | `1.2.0-0.ci417` |

RPM compares the release field segment by segment, so `0.ci417` sorts below `1`
and a CI build never shadows the tagged release of the same version.

---

## 5. What CI does

1. **build (linux leg)** runs `scripts/ci/build_linux_source_packages.sh`, which
   stages `dist/obs/` with the tarball, the version-synced spec, and the
   rpmlintrc, then checks the tarball actually contains the payload. Uploaded as
   the `linux-source-packages` artifact.
2. **release (`obs_rpm` leg)** downloads that artifact, reads the OBS credentials
   from Vault, and runs `scripts/ci/publish_obs_package.sh`.

If publishing is enabled and no credentials are available, the job **fails**.
Set `OBS_REQUIRE_PUBLISH=false` (the `require-publish` action input) to downgrade
that to a skip. Disable the lane for a manual run with the `publish_obs_package`
input of **Run workflow**.

---

## 6. Building and publishing locally

```bash
# Stage the payload, tarball, spec, and rpmlintrc into dist/obs/
make package-rpm-source

# Publish with osc
OBS_USERNAME=<user> OBS_PASSWORD=<password> \
  bash scripts/ci/publish_obs_package.sh
```

`make package-rpm-source` runs `flutter build linux --release` first if
`build/linux/x64/release/bundle` is missing, so it must run on Linux. If
`rpmbuild` is installed it also produces a local `.src.rpm` for inspection; OBS
rebuilds from the tarball and spec regardless.

---

## 7. End-user installation

Replace `home:/haitaopanhq` below if the project was overridden.

### openSUSE (`zypper`)

```bash
sudo zypper addrepo https://download.opensuse.org/repositories/home:/haitaopanhq/openSUSE_Tumbleweed/home:haitaopanhq.repo
sudo zypper refresh
sudo zypper install xworkmate
```

### Fedora / RHEL / CentOS Stream (`dnf`)

```bash
sudo dnf config-manager --add-repo https://download.opensuse.org/repositories/home:/haitaopanhq/Fedora_40/home:haitaopanhq.repo
sudo dnf install xworkmate
```
