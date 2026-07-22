# Open Build Service (OBS) & RPM Packaging Guide

This guide describes how the **AI Workspace Lab** team packages and releases **XWorkmate** (`xworkmate`) to the **Open Build Service (OBS)** (`build.opensuse.org`) for Fedora, RHEL, openSUSE, and CentOS distributions.

---

## 1. OBS & RPM Architecture Overview

| Property | Value | Description |
| :--- | :--- | :--- |
| **Build Service Platform** | Open Build Service (OBS) | `https://build.opensuse.org` |
| **OBS Home / Org Project** | `home:ai-workspace-lab` | Primary project namespace |
| **OBS Package Identifier** | `xworkmate-app` | Package entry inside OBS project |
| **Target Distributions** | openSUSE Leap/Tumbleweed, Fedora, RHEL/CentOS | Multi-distro build matrix |
| **RPM Spec File** | `packaging/rpm/xworkmate.spec` | Fedora / openSUSE packaging specification |
| **RPM Package Name** | `xworkmate` | Executable package installed via `dnf` / `zypper` |

---

## 2. Setting Up OBS Project & SCM/CI Integration

### Step 1: Create OBS Account & Home Project
1. Visit `https://build.opensuse.org` and register or log in.
2. Your primary home namespace is `home:<your-username>` or your team project `home:ai-workspace-lab`.

### Step 2: Create Package
1. Under `home:ai-workspace-lab`, click **Add Package** (or **Create Package**).
2. Name: `xworkmate-app`
3. Title: `XWorkmate Desktop Shell`
4. Description: `XWorkmate Linux desktop shell with GNOME/KDE proxy and tunnel integration.`

### Step 3: Configure Target Repositories
In the OBS project settings, add build target platforms:
- **Fedora** (e.g. Fedora 40, Fedora 41)
- **openSUSE** (openSUSE Tumbleweed, openSUSE Leap 15.6)
- **RedHat / CentOS** (RHEL 9 / CentOS Stream)

### Step 4: Configure GitHub SCM/CI Webhook Link
OBS supports SCM/CI workflow links with GitHub:
1. In OBS package view, add `_service` or use the OBS SCM/CI integration page.
2. Link URL: `https://github.com/ai-workspace-lab/xworkmate-app.git`
3. Branch: `main`
4. When new commits are pushed to `main`, OBS automatically fetches updated sources, runs `rpmbuild`, and produces multi-distro RPMs.

---

## 3. Building SRPM and Uploading via `osc` CLI

You can build RPM source packages (`.src.rpm` / SRPM) locally and manage OBS packages using the `osc` CLI tool:

### 1. Generate SRPM locally
```bash
make package-rpm-source
# or
bash scripts/package-rpm-source.sh
```
This generates `xworkmate-<version>.tar.gz` and `xworkmate.spec` under `dist/rpm/`.

### 2. Checkout & Commit to OBS using `osc`
```bash
# Install osc tool (openSUSE: zypper in osc | Fedora: dnf install osc | macOS: brew install osc)
osc checkout home:ai-workspace-lab xworkmate-app
cd home:ai-workspace-lab/xworkmate-app

# Copy staged tarball and spec
cp /path/to/xworkmate-app/dist/rpm/xworkmate-*.tar.gz .
cp /path/to/xworkmate-app/dist/rpm/xworkmate.spec .

# Stage and commit
osc addremove
osc commit -m "Release version 1.1.9"
```

---

## 4. End-User Installation Guide

Once OBS completes building the RPMs, users can install XWorkmate using their native package managers:

### Fedora / RHEL / CentOS Stream (`dnf`)
```bash
# 1. Add AI Workspace Lab OBS Repository
sudo dnf config-manager --add-repo https://download.opensuse.org/repositories/home:/ai-workspace-lab/Fedora_40/home:ai-workspace-lab.repo

# 2. Install XWorkmate
sudo dnf install xworkmate
```

### openSUSE Tumbleweed / Leap (`zypper`)
```bash
# 1. Add repository
sudo zypper addrepo https://download.opensuse.org/repositories/home:/ai-workspace-lab/openSUSE_Tumbleweed/home:ai-workspace-lab.repo

# 2. Refresh and install
sudo zypper refresh
sudo zypper install xworkmate
```
