# ADR: Refactor Style Baseline Uses No-`part` File Organization

- Status: Accepted
- Date: 2026-03-28
- Owner: XWorkmate maintainers

## Context

The codebase previously mixed multiple split styles (`part`-based and import-based splits), which created unclear review standards and inconsistent refactor outcomes.

The repository has already migrated away from Dart `part` declarations in production/test code, while workflow and skill references still mention both styles.

## Decision

We standardize on **no-`part`** organization for this repository:

- Use import-based closure files and explicit ownership boundaries.
- Keep one business closure per file family (root + closure-owned supporting files).
- Avoid introducing new `part` / `part of` declarations.

## Single Source of Enforcement

`AGENTS.md` section **Refactor Workflow Standard** is the only normative enforcement source.

This ADR is historical rationale and does not define additional runtime enforcement rules.
If this ADR and `AGENTS.md` ever diverge, `AGENTS.md` wins.

## Consequences

- Refactor reviews no longer debate split style; they focus on closure ownership and behavior safety.
- File-size and closure guards should target implementation-bearing files instead of thin export anchors.
- Existing helper files remain valid only when closure-owned; generic helper sprawl is disallowed.

## Verification Checklist

- No new `part` / `part of` usage in `lib/` and `test/`.
- Refactor plans and implementations follow `RED -> GREEN -> REFACTOR -> REGRESSION`.
- Triggered refactor tasks satisfy the `Done Criteria` in `AGENTS.md`.
