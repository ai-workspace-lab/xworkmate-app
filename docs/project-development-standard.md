# Project Development Standard

This page defines the repository-wide working standard for branch usage,
release tagging, and secret incident handling.

## 1. Branch Roles

| Ref | Role | Typical Lifetime | Lands Into |
|---|---|---|---|
| `main` | Main timeline / trunk | Long-lived | Receives `feature/*`, `bugfix/*`, `cherry-pick/*` |
| `release/*` | LTS maintenance line | Long-lived, version-scoped | Receives `hotfix/*` and, when intentional, `backport/*` |
| `feature/*` | New feature work | Short-lived | `main` |
| `bugfix/*` | Normal bug fix work for trunk | Short-lived | `main` |
| `hotfix/*` | Urgent fix for a published release line | Short-lived | `release/*` |
| `cherry-pick/*` | Single-fix return path from release to main | Short-lived | `main` |
| `backport/*` | Single-fix or scoped fix from main to release | Short-lived | `release/*` |
| `tag` | Published release snapshot | Immutable | Marks a release point |

## 2. Allowed Paths

- `feature/*` -> `main`
- `bugfix/*` -> `main`
- `hotfix/*` -> `release/*`
- `cherry-pick/*` -> `main`
- `backport/*` -> `release/*`
- `tag` from `main` or an intentional `release/*` release point

For pull requests, the target branch must match the landing branch:

- `feature/*`, `bugfix/*`, `cherry-pick/*` PRs must target `main`
- `hotfix/*`, `backport/*` PRs must target `release/*`
- `backport/*` is never a valid source branch for a PR into `main`
- `cherry-pick/*` is never a valid source branch for a PR into `release/*`

## 3. Disallowed Paths

- `release/*` -> `main`
- `main` -> `release/*`
- `feature/*` -> `release/*`
- `hotfix/*` -> `main`
- `release/*` -> `release/*`
- routine `tag` creation from anywhere other than a deliberate release point

## 4. Release Lifecycle

### Release Cut

A `release/*` branch is created from a reviewed, stable commit on `main` when a
version enters its release phase.

```text
main ── stable commit ──> release/v1.2
```

- Use the name `release/vMAJOR.MINOR` (for example, `release/v1.2`).
- Record the source commit and planned version in the release PR or release
  notes.
- After the cut, new feature work continues on `main`; the release branch only
  accepts `hotfix/*` and intentional `backport/*` changes.
- Do not merge `main` wholesale into a release branch.

### Publishing and Maintenance

Each published build is an immutable tag on the applicable release point.

```text
release/v1.2 ──> v1.2.0 ──> v1.2.1 ──> v1.2.2
                   release      hotfix     backport
```

- Publish a GitHub Release and production artifacts from the same tag.
- Every artifact must be traceable to one unique release tag.
- A maintained release branch remains version-scoped and accepts only the
  controlled changes defined above.
- When support ends, mark the branch as EOL in release notes and protect it as
  read-only; retain it for history and reproducibility.

## 5. Versioning and Tag Rules

This repository follows [Semantic Versioning 2.0.0](https://semver.org/).

### Version Format

All published release tags use `vMAJOR.MINOR.PATCH`:

```text
v1.2.3
```

| Component | Increment when | Example |
|---|---|---|
| `MAJOR` | A breaking public API, configuration, protocol, or migration change is introduced | `v2.0.0` |
| `MINOR` | Backward-compatible functionality is added | `v1.3.0` |
| `PATCH` | Backward-compatible fixes, security maintenance, or release-ready documentation changes are published | `v1.2.4` |

Pre-release tags are allowed only for validation and must use a SemVer suffix:

```text
v1.3.0-alpha.1
v1.3.0-beta.1
v1.3.0-rc.1
```

`alpha` is for early testing, `beta` is feature-complete testing, and `rc` is
the final release-candidate validation stage. Pre-release tags must not be
reused or moved.

### Tag Governance

- A tag is a release snapshot, not a working branch.
- Use annotated tags to mark published versions and maintenance cut points.
- Create tags intentionally, never as a side effect of branch synchronization.
- A release tag must point to an intentional `release/*` publication commit, or
  to the approved `main` commit for a release that has no maintenance branch.
- Published tags are immutable: never force-update, delete, or reuse one.
- Configure repository tag protection for `v*` so only release maintainers can
  create release tags.
- Each published release includes a version, date, changelog, and any breaking
  changes, migration notes, or security notices.

## 6. Pull Request and Merge Strategy

### Pull Request Requirements

Every pull request must contain:

- a concise description of the user or engineering outcome;
- links to the issue, task, or original PR when one exists;
- the verification performed, including any intentionally unrun checks and why;
- migration, configuration, security, or rollback notes when the change can
  affect existing users or deployments.

Release maintenance PRs additionally identify the target `release/*` branch.
`backport/*` and `cherry-pick/*` PRs must link the original change and state
why the cross-branch transfer is required.

### Merge Policy

- Prefer a squash merge for `feature/*` and `bugfix/*` PRs so `main` retains
  one reviewable commit per logical change.
- Keep `hotfix/*`, `backport/*`, and `cherry-pick/*` changes small and
  traceable. Preserve the original commit SHA in the PR description when it is
  relevant to release maintenance.
- Update a PR by rebasing or resolving conflicts on its source branch; do not
  merge a base branch into a release-maintenance branch merely to make it
  mergeable.
- Merge only after required reviews and required checks pass. Revert production
  regressions through a new PR rather than force-pushing shared history.

## 7. CI/CD, Review, and Ownership Gates

### Required Gates

Protected `main` and supported `release/*` branches must require the branch
policy check, required reviews, and the applicable verification before merge.
The current repository workflows provide these baseline signals:

| Gate | Current workflow or command | Purpose |
|---|---|---|
| Branch direction | `Validate Release PR` | Enforces allowed source/target branch pairs for `main` and `release/*` PRs |
| PR quality | `PR Layered Tests` | Runs dependency resolution, `flutter analyze`, unit/widget tests, and available golden tests for PRs into `main` |
| Build verification | `Build and Release XWorkmate Packages` | Runs the Flutter CI suite and package builds for supported main/release/tag events |
| Release E2E | `Release E2E Gates` | Runs scheduled or manually dispatched integration checks; Patrol is currently non-blocking |

Changes that affect native packaging, permissions, authentication, secrets, or
release scripts require the relevant targeted tests in addition to the normal
PR checks. The exact security-sensitive verification is defined in
[`docs/security/secure-development-rules.md`](security/secure-development-rules.md).

### Ownership and Protected Branches

- Maintain branch protection for `main` and every supported `release/*` line:
  no direct pushes, required checks, at least one approval, and no force pushes.
- Add a `.github/CODEOWNERS` file before assigning required ownership review.
  Owners must be real maintainers for their areas; do not use placeholder
  accounts. At minimum, cover `.github/`, `ios/`, `macos/`, `android/`,
  security-sensitive runtime code, and release scripts.
- Changes to CI, release policy, native entitlements, or security boundaries
  require review from the responsible maintainer in addition to the author.

### Secret Prevention

- Enable GitHub secret scanning and push protection when available for the
  repository.
- Run a secret scanner such as Gitleaks in CI before making it a required
  branch check; false-positive rules must be reviewed rather than broadly
  bypassed.
- A secret-scanning gate prevents new leakage but does not replace the incident
  flow below when a secret is already exposed.

## 8. Backport vs Cherry-Pick

### `backport/*`

- Use `backport/*` when a fix starts on `main` and must be applied to a
  `release/*` line.
- Open the PR against the relevant `release/*` branch.
- Keep the scope narrow.
- Prefer one fix or one tightly related fix set per branch.
- Link the original PR or issue and state why the release line needs the change.

### `cherry-pick/*`

- Use `cherry-pick/*` when a fix starts on `release/*` and must be applied back
  to `main`.
- Open the PR against `main`.
- Keep the scope narrow.
- Use it only for a single fix or one tightly related fix set.

### Boundary

- `backport/*` moves from `main` to `release/*`.
- `cherry-pick/*` moves from `release/*` to `main`.
- Do not use the two branch types interchangeably.

## 9. Emergency Secret Incident Flow

If a secret, token, password, certificate, or private key is accidentally
committed:

1. Revoke the leaked credential immediately.
2. Generate or rotate a replacement credential.
3. Review access logs and audit trails for suspicious use.
4. Rewrite Git history only after the credential is no longer valid.
5. Force-push the rewritten branches and tags.
6. Have collaborators `git fetch --all` and re-align local branches as needed.

### Cleanup Example

```bash
git filter-repo --path path/to/secret.env --invert-paths
git push origin --force --all
git push origin --force --tags
```

## 10. TL;DR

- `main` is the trunk.
- `release/*` is the LTS maintenance line.
- Create `release/vMAJOR.MINOR` from a stable `main` commit; it accepts only
  controlled maintenance changes.
- `feature/*` and `bugfix/*` go to `main`.
- `hotfix/*` goes to `release/*`.
- `backport/*` goes from `main` to `release/*`.
- `cherry-pick/*` goes from `release/*` to `main`.
- PR target and branch kind must match the same direction.
- PRs require a clear purpose, verification record, and applicable review; use
  squash merges for normal feature and bug-fix work.
- Protected branches require CI, review, ownership, and secret-prevention
  gates.
- Release tags use SemVer: `vMAJOR.MINOR.PATCH`; published tags are immutable.
- Secret leaks are handled by revocation first, history rewriting second.
