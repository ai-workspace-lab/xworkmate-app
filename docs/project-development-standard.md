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

## 3. Disallowed Paths

- `release/*` -> `main`
- `main` -> `release/*`
- `feature/*` -> `release/*`
- `hotfix/*` -> `main`
- `release/*` -> `release/*`
- routine `tag` creation from anywhere other than a deliberate release point

## 4. Tag Rules

- A tag is a release snapshot, not a working branch.
- Use tags to mark published versions and maintenance cut points.
- Tags should be created intentionally, never as a side effect of branch sync.
- Tags may be used to cut a new `release/*` line.

## 5. Backport vs Cherry-Pick

### `backport/*`

- Use `backport/*` when a fix starts on `main` and must be applied to a
  `release/*` line.
- Keep the scope narrow.
- Prefer one fix or one tightly related fix set per branch.

### `cherry-pick/*`

- Use `cherry-pick/*` when a fix starts on `release/*` and must be applied back
  to `main`.
- Keep the scope narrow.
- Use it only for a single fix or one tightly related fix set.

### Boundary

- `backport/*` moves from `main` to `release/*`.
- `cherry-pick/*` moves from `release/*` to `main`.
- Do not use the two branch types interchangeably.

## 6. Emergency Secret Incident Flow

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

## 7. TL;DR

- `main` is the trunk.
- `release/*` is the LTS maintenance line.
- `feature/*` and `bugfix/*` go to `main`.
- `hotfix/*` goes to `release/*`.
- `backport/*` goes from `main` to `release/*`.
- `cherry-pick/*` goes from `release/*` to `main`.
- `tag` marks a release snapshot.
- Secret leaks are handled by revocation first, history rewriting second.
