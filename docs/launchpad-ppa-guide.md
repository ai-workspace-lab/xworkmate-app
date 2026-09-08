# Launchpad PPA & Debian (.deb) Packaging Guide

How **XWorkmate** (`xworkmate`) is packaged and published to the AI Workspace Lab
Launchpad PPA.

---

## 1. Why the source package ships a prebuilt bundle

Launchpad builds every upload from source inside a clean chroot that has **no
Flutter SDK and no network access**. XWorkmate cannot be compiled there.

So the source package carries the already-compiled release bundle as
`payload.tar.gz`, and `debian/rules` only unpacks it into place:

```
opt/xworkmate/…                                  Flutter release bundle
usr/share/applications/xworkmate.desktop         desktop entry
usr/share/icons/hicolor/scalable/apps/…          icon
usr/share/xworkmate/autostart/xworkmate.desktop  autostart entry
```

`scripts/package-linux-payload.sh` stages that tree from
`build/linux/x64/release/bundle`, which the Linux build leg has already produced.

It ships as an **archive rather than a loose tree** for a reason worth
remembering: `dpkg-source` applies default tar-ignore patterns when it builds
the source tarball, and those patterns cover `*.so`, `*.a`, and `*.o`. A loose
tree loses every shared library in the bundle — `libapp.so` and
`libflutter_linux_gtk.so` included — with no warning, producing a package that
installs an executable with no engine and no application code.
`scripts/ci/build_linux_source_packages.sh` compares the payload's round trip
file by file so that cannot reach an archive.

Consequences worth knowing:

* The package is `Architecture: amd64` only. The payload is an x86-64 build.
* `dh_shlibdeps`, `dh_strip`, and `dh_makeshlibs` are disabled — they would
  either rewrite the vendored binaries or derive dependencies on the bundle's
  own private sonames. Runtime dependencies are declared explicitly in
  `debian/control`, using alternatives (`libgtk-3-0 | libgtk-3-0t64`) so the
  same package resolves on both jammy and noble.

---

## 2. Infrastructure

| Property | Value |
| :--- | :--- |
| Launchpad team | [`ai-workspace-lab`](https://launchpad.net/~ai-workspace-lab) |
| PPA | `ppa:ai-workspace-lab/ppa` |
| Debian package name | `xworkmate` |
| Target series | `jammy` (22.04), `noble` (24.04) |

One-time setup:

1. Create the Launchpad team `ai-workspace-lab` and set its membership policy to
   **Restricted** or **Closed** — open teams cannot own a PPA.
2. Create the PPA named `ppa` under that team.
3. Register the signing GPG key on the Launchpad account that uploads, and make
   sure that account has upload rights to the PPA. See
   [GPG Key & Vault Setup Guide](gpg-key-vault-setup-guide.md).

---

## 3. Versioning

Launchpad accepts a given version **once**, and each series needs its own
upload, so every source package gets a distinct version:

| Build | Version |
| :--- | :--- |
| Tagged release, jammy | `1.2.0~ubuntu22.04.1` |
| Tagged release, noble | `1.2.0~ubuntu24.04.1` |
| Untagged CI build, jammy | `1.2.0~ci417~ubuntu22.04.1` |

The `~ciN` marker sorts *below* the plain release, so a CI build of `1.2.0` never
shadows the eventual `1.2.0` release; `~ubuntu22.04.1` sorts below
`~ubuntu24.04.1`, so a release upgrade keeps moving forward.
`scripts/ci/build_linux_source_packages.sh` asserts both orderings with
`dpkg --compare-versions` on every build.

Override the trailing `.1` with `PPA_PACKAGE_REVISION` when a packaging-only fix
has to be re-uploaded for an unchanged upstream version. Override the series list
with `PPA_SERIES="jammy:22.04 noble:24.04"`.

---

## 4. What CI does

In `.github/workflows/build-and-release.yml`:

1. **build (linux leg)** compiles the app, then runs
   `scripts/ci/build_linux_source_packages.sh`, which stages the payload, builds
   one unsigned source package per series, and verifies each one unpacks with the
   payload and packaging intact and targets a real Ubuntu series. This runs on
   every build, pull requests included, so packaging breaks surface here rather
   than against the live archive. The results upload as the
   `linux-source-packages` artifact.
2. **release (`launchpad_ppa` leg)** downloads that artifact, pulls
   `GPG_PRIVATE_KEY` / `GPG_KEY_ID` / `GPG_PASSPHRASE` from Vault, then runs
   `scripts/ci/publish_launchpad_ppa.sh`, which signs each `.changes` with
   `debsign`, verifies the signature, and uploads with `dput`.

If publishing is enabled and the credentials are missing, the job **fails**.
Set `PPA_REQUIRE_UPLOAD=false` (the `require-upload` action input) to downgrade
that to a skip.

Disable the lane for a manual run with the `publish_ppa_package` input of
**Run workflow**.

---

## 5. Building and uploading locally

```bash
# Stage the payload and build one source package per series
make package-deb-source

# Inspect what would be uploaded
ls dist/ppa/*/

# Sign and upload (needs devscripts + dput, and a key with PPA upload rights)
GPG_PRIVATE_KEY="$(gpg --export-secret-keys --armor <KEY_ID> | base64 | tr -d '\n')" \
GPG_KEY_ID=<KEY_ID> \
  bash scripts/ci/publish_launchpad_ppa.sh
```

`make package-deb-source` runs `flutter build linux --release` first if
`build/linux/x64/release/bundle` is missing, so it must run on Linux.

---

## 6. Troubleshooting

| Symptom | Cause |
| :--- | :--- |
| `Unable to find distroseries: unstable` | The changelog targets a Debian suite. Launchpad only accepts Ubuntu series names; `build_linux_source_packages.sh` rejects this before upload. |
| `File xworkmate_… already exists` | That exact version was already accepted. Bump `PPA_PACKAGE_REVISION`. |
| `GPG signature verification failed` | The key is not registered on the uploading Launchpad account, or `GPG_PASSPHRASE` is missing for a protected key. |
| Package installs but does not start | The payload was staged from a stale `build/linux/x64/release/bundle`. Remove it and rebuild. |

---

## 7. End-user installation

```bash
sudo add-apt-repository ppa:ai-workspace-lab/ppa
sudo apt update
sudo apt install xworkmate
```
