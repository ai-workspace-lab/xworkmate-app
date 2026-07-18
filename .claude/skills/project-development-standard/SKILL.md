---
name: project-development-standard
description: Repository-wide branching, PR, release, tagging, and secret-incident rules for this repo. Use whenever creating a branch, opening or reviewing a pull request, choosing a PR target (main vs release/*), backporting or cherry-picking a fix, cutting a release, creating a version tag, or responding to a committed secret. Also use to validate that an existing branch name and its PR target match the allowed directions.
---

# Project Development Standard

Authoritative source: [docs/project-development-standard.md](../../../docs/project-development-standard.md).
This skill is the operational digest; when in doubt, read the full document.

## Golden rules

1. Never push directly to `main` or any `release/*` branch — every change lands through a PR, including docs-only changes and locally stranded commits.
2. Branch kind determines the PR target. Never mix directions.
3. Published tags are immutable. Never force-update, delete, or reuse one.
4. If a secret was committed: revoke it FIRST, rewrite history second (see below).

## Branch kinds and PR targets

| Branch | Purpose | PR target |
|---|---|---|
| `feature/*` | New feature work | `main` |
| `bugfix/*` | Normal bug fix for trunk | `main` |
| `hotfix/*` | Urgent fix for a published release line | `release/*` |
| `backport/*` | Fix moving from `main` to a release line | `release/*` |
| `cherry-pick/*` | Fix moving from a release line back to `main` | `main` |

Disallowed: `release/*`→`main`, `main`→`release/*` wholesale merges, `feature/*`→`release/*`, `hotfix/*`→`main`, `backport/*`→`main`, `cherry-pick/*`→`release/*`.

Before opening a PR, verify: source branch prefix matches the target branch per the table above. The `Validate Release PR` workflow enforces this; do not fight it.

## Opening a PR — required content

Every PR body must include:

- what user or engineering outcome the change delivers (one concise paragraph);
- links to the issue / task / original PR when one exists;
- the verification performed — name the exact test commands and results, and call out any intentionally unrun checks with the reason;
- migration, configuration, security, or rollback notes when the change can affect existing users or deployments.

Additionally for maintenance PRs:

- `hotfix/*` / `backport/*`: name the target `release/*` branch explicitly.
- `backport/*` / `cherry-pick/*`: link the original change, preserve the original commit SHA in the description, and state why the cross-branch transfer is required.

Public-repo hygiene: this repository is public. PR bodies, commit messages, and committed docs must not contain credentials, tokens, internal hostnames, deploy targets, secret-store paths, or other internal infrastructure details.

## Merge policy

- Squash-merge `feature/*` and `bugfix/*` PRs — one reviewable commit per logical change on `main`.
- Keep `hotfix/*`, `backport/*`, `cherry-pick/*` small and traceable.
- Update a PR by rebasing its source branch; do not merge the base branch into a release-maintenance branch just to make it mergeable.
- Merge only after required reviews and required checks pass. Revert regressions with a new PR, never by force-pushing shared history.

## Releases and tags

- Cut `release/vMAJOR.MINOR` from a reviewed, stable `main` commit; after the cut it accepts only `hotfix/*` and intentional `backport/*`.
- Tags are SemVer `vMAJOR.MINOR.PATCH` (pre-releases: `-alpha.N` / `-beta.N` / `-rc.N`), annotated, created deliberately at a release point — never as a side effect of branch synchronization.
- Every published artifact must trace to exactly one release tag; each release records version, date, changelog, and any breaking/migration/security notes.

## Backport vs cherry-pick (direction cheat)

- Fix born on `main`, needed on a release line → `backport/*` → PR into `release/*`.
- Fix born on `release/*`, needed on trunk → `cherry-pick/*` → PR into `main`.
- One fix (or one tightly related fix set) per branch.

## Committed secret — emergency flow

1. Revoke the leaked credential immediately (before anything else).
2. Generate/rotate the replacement.
3. Review access logs for suspicious use.
4. Only after the credential is dead: rewrite history (`git filter-repo --path <file> --invert-paths`), then force-push branches and tags.
5. Tell collaborators to `git fetch --all` and re-align local branches.

A secret-scanning CI gate prevents new leaks but never replaces this flow for an already-exposed secret.

## CI gates to expect on PRs

| Gate | Workflow |
|---|---|
| Branch direction | `Validate Release PR` |
| Analyze + unit/widget/golden tests | `PR Layered Tests` (PRs into `main`) |
| Build verification | `Build and Release XWorkmate Packages` |
| Release E2E | `Release E2E Gates` (scheduled/dispatched; Patrol non-blocking) |

Changes touching native packaging, permissions, authentication, secrets, or release scripts need the targeted tests from `docs/security/secure-development-rules.md` in addition to normal PR checks.
