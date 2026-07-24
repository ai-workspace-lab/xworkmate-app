# Task Record: Ubuntu PPA & Open Build Service (OBS) GitHub Actions Refactoring

- **Date**: 2026-07-24
- **Author**: AI Workspace Lab CI/CD Team
- **Status**: Completed

---

## 1. Requirement & Research Findings

### Requirement
Analyze whether the Ubuntu PPA publishing logic (`publish_launchpad_ppa.sh`) and Open Build Service (OBS) trigger logic (`trigger_obs_build.sh`) can be encapsulated into reusable GitHub Actions, evaluate whether off-the-shelf Actions exist in the GitHub Marketplace, add `workflow_dispatch` parameter controls (`publish_ppa_package` and `publish_obs_package`), and refactor the workflow.

---

## 2. Analysis of Existing Off-the-Shelf GitHub Actions

### A. Launchpad PPA Publishing
- **Marketplace Actions Found**:
  - `yuezk/publish-ppa-package`: Automates Debian package building, GPG signing, and `dput` upload.
  - `AptiviCEO/actions-launchpad-ppa-push-template`: Template repository for Launchpad PPA releases.
- **Evaluation for `xworkmate-app`**:
  - *Off-the-shelf actions* expect standard Debian project structures and direct repo secret access.
  - `xworkmate-app` uses custom multi-platform Flutter/Go pre-packaging source tarball staging ([scripts/package-debian-source.sh](file:///Users/shenlan/workspaces/ai-workspace-lab/xworkmate-app/scripts/package-debian-source.sh)) and HashiCorp Vault JWT secret integration.
  - **Conclusion**: A project-tailored Composite Action at `.github/actions/publish-launchpad-ppa` is superior because it encapsulates the project's exact GPG key loading, source packaging, signing, and `dput` upload workflow.

### B. Open Build Service (OBS) Trigger
- **Existing Mechanisms Found**:
  - **OBS Native SCM/CI Webhooks (`.obs/workflows.yml`)**: Open Build Service natively supports receiving GitHub webhooks to trigger build workflows.
  - **HTTP Request Actions (`fjogeleit/http-request-action`)**: Generic HTTP POST action to trigger `https://build.opensuse.org/trigger/runservice`.
- **Evaluation for `xworkmate-app`**:
  - A project-tailored Composite Action at `.github/actions/trigger-obs-build` cleanly encapsulates the OBS API token authorization, POST payload, parameter defaults (`home:haitaopanhq/xworkmate`), and graceful non-blocking error handling.

---

## 3. Custom GitHub Actions Architecture & Workflow Dispatch Control

### Action 1: `.github/actions/publish-launchpad-ppa`
- **Type**: Composite GitHub Action (`action.yml`)
- **Inputs**: `gpg-private-key`, `gpg-key-id`, `ppa-target` (default: `ppa:ai-workspace-lab/ppa`).

### Action 2: `.github/actions/trigger-obs-build`
- **Type**: Composite GitHub Action (`action.yml`)
- **Inputs**: `obs-token`, `obs-project` (default: `home:haitaopanhq`), `obs-package` (default: `xworkmate`), `obs-url` (default: `https://build.opensuse.org/trigger/runservice`).

### Workflow Dispatch Control Inputs
Added to `.github/workflows/build-and-release.yml`:
- `publish_ppa_package`: Boolean (default `true`) - Controls Debian source package build and Launchpad PPA publish.
- `publish_obs_package`: Boolean (default `true`) - Controls Open Build Service RPM build trigger.

---

## 4. Implementation Steps Checklist

- [x] Create task documentation in `docs/tasks/2026-07-24-ppa-obs-github-actions-refactoring.md`.
- [x] Create `.github/actions/publish-launchpad-ppa/action.yml`.
- [x] Create `.github/actions/trigger-obs-build/action.yml`.
- [x] Add `publish_ppa_package` and `publish_obs_package` inputs to `workflow_dispatch` in `build-and-release.yml`.
- [x] Refactor `.github/workflows/build-and-release.yml` to consume both composite actions.
- [x] Update `trigger_obs_build.sh` and `publish_launchpad_ppa.sh` for parameter flexibility.
- [x] Run syntax checks and commit changes to `bugfix/ci-vault-obs-ppa-fix`.
- [x] Push branch to origin and verify GitHub Actions workflow run.
