# Launchpad PPA & Debian (.deb) Packaging Guide

This guide describes how the **AI Workspace Lab** team packages and releases **XWorkmate** (`xworkmate`) to Launchpad PPA and Debian/Ubuntu distributions.

---

## 1. Launchpad Infrastructure Architecture

| Property | Value | Description |
| :--- | :--- | :--- |
| **Team / Organization** | `ai-workspace-lab` | Launchpad Team owning the PPA (`https://launchpad.net/~ai-workspace-lab`) |
| **Membership Policy** | `Restricted` or `Closed` | Mandatory for creating PPAs on Launchpad |
| **PPA Identifier** | `ppa:ai-workspace-lab/ppa` | Official Ubuntu PPA repository |
| **Application Project** | `xworkmate-app` | Launchpad Project (`https://launchpad.net/xworkmate-app`) |
| **GitHub Source** | `https://github.com/ai-workspace-lab/xworkmate-app.git` | Imported Git repository |
| **Debian Package Name** | `xworkmate` | Package name installed via `apt install xworkmate` |

---

## 2. Launchpad Setup Steps

### Step 1: Create Team
1. Visit `https://launchpad.net/people/+newteam`.
2. Name: `ai-workspace-lab`
3. Display Name: `AI Workspace Lab`

### Step 2: Configure Membership Policy (Required for PPA)
1. Go to `https://launchpad.net/~ai-workspace-lab/+edit`.
2. Set **Membership policy** (or Subscription policy) to **Restricted** or **Closed**.
3. Save changes. *(Open or Delegated teams cannot create PPAs on Launchpad).*

### Step 3: Create Team PPA
1. Go to `https://launchpad.net/~ai-workspace-lab`.
2. Click **Create a new PPA**.
3. PPA Name: `ppa` (Full identifier: `ppa:ai-workspace-lab/ppa`).
4. Display Name: `AI Workspace Lab PPA`.

### Step 4: Import Git Repository
1. Go to `https://launchpad.net/projects/+new` and create project `xworkmate-app` owned by `ai-workspace-lab`.
2. Go to `https://code.launchpad.net/xworkmate-app` and click **Import a Git repository**.
3. Source URL: `https://github.com/ai-workspace-lab/xworkmate-app.git`
4. Target Launchpad repository: `https://git.launchpad.net/~ai-workspace-lab/xworkmate-app`.

---

## 3. Repository Packaging Files (`debian/`)

The repository contains standard Debian packaging metadata in the `debian/` directory:

* `debian/control`: Package metadata, build dependencies (`debhelper-compat (= 13)`, `cmake`, `clang`, etc.), runtime dependencies (`network-manager`, `libgtk-3-0`, `libglib2.0-0`), maintainer, homepage.
* `debian/rules`: Executable dh build rules invoking `flutter build linux --release` and staging output binaries to `/opt/xworkmate/` and `/usr/share/`.
* `debian/changelog`: Version history adhering to Debian standard changelog format.
* `debian/copyright`: DEP-5 machine-readable license file.
* `debian/source/format`: Set to `3.0 (native)`.
* `debian/postinst`: Post-installation script refreshing desktop database and GTK icon cache.
* `debian/postrm`: Post-removal script refreshing desktop database and GTK icon cache.

---

## 4. Building Debian Source Packages Locally

To generate Debian source packages ready for Launchpad PPA upload, run:

```bash
make package-deb-source
# or
bash scripts/package-debian-source.sh
```

This script will:
1. Extract the current release version from `pubspec.yaml`.
2. Stage the clean source tree into `dist/debian/xworkmate-<version>`.
3. If `dpkg-buildpackage` is available (Ubuntu/Debian environment), run `dpkg-buildpackage -S -us -uc` to produce `.dsc`, `.tar.xz`, and `_source.changes` files under `dist/debian/`.

---

## 5. Uploading to Launchpad PPA via `dput`

1. Generate GPG Key and import into Launchpad account (`https://launchpad.net/~your-username/+editpgpkeys`). For complete details on GPG generation and Vault secret provisioning (`GPG_PRIVATE_KEY` and `GPG_KEY_ID`), see the [GPG Key & Vault Setup Guide](file:///Users/shenlan/workspaces/ai-workspace-lab/xworkmate-app/docs/gpg-key-vault-setup-guide.md).
2. Build the signed source package:
   ```bash
   cd dist/debian/xworkmate-<version>
   dpkg-buildpackage -S -k<YOUR-GPG-KEY-ID>
   ```
3. Upload the resulting `.changes` file to the Launchpad PPA:
   ```bash
   dput ppa:ai-workspace-lab/ppa dist/debian/xworkmate_<version>_source.changes
   ```
4. Monitor the build progress on `https://launchpad.net/~ai-workspace-lab/+archive/ubuntu/ppa`.


---

## 6. End-User Installation Guide

Once the PPA build finishes on Launchpad, Ubuntu/Debian users can install XWorkmate using standard `apt`:

```bash
# 1. Add AI Workspace Lab PPA
sudo add-apt-repository ppa:ai-workspace-lab/ppa

# 2. Update package index
sudo apt update

# 3. Install XWorkmate
sudo apt install xworkmate
```
