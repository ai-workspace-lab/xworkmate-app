---
name: xworkmate-worktree-task-mode
description: Default XWorkmate task execution mode: create an isolated git worktree, use parallel lanes for bounded independent work, verify, merge to main, and clean up.
---

# XWorkmate Worktree Task Mode

Use this skill as the default execution path for non-trivial work in this repository.

## Goals

- Keep the main checkout clean.
- Isolate implementation in a temporary worktree created from `main`.
- Use concurrent lanes only when the subtasks are genuinely independent.
- Finish the lifecycle: verify, merge back to `main`, remove the temporary worktree.

## Default Flow

1. Inspect the current repo state from the main checkout.
2. Create a temporary branch and `git worktree` from `main`.
3. Do the critical-path implementation locally in the worktree.
4. If helpful, delegate bounded side work in parallel, but avoid blocking the main lane on exploratory tasks.
5. Run the smallest relevant verification first, then broader checks when needed.
6. Merge the finished branch back into `main`.
7. Remove the temporary worktree and branch if they are no longer needed.

## Guardrails

- Do not use a worktree for tiny read-only or one-command tasks unless it materially helps.
- Do not ask the user to re-confirm this mode on every task; it is the repo default.
- Do not leave temporary worktrees behind after the task is complete unless the user explicitly wants that.
- Preserve user changes and do not revert unrelated work.
