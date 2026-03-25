---
name: xworkmate-worktree-task-mode
description: Mandatory XWorkmate task execution mode: every task starts in an isolated git worktree, implementation is verified and committed there, then merged back into main and cleaned up.
---

# XWorkmate Worktree Task Mode

Use this skill as the required execution path for work in this repository unless the user explicitly asks for a different flow.

## Goals

- Keep `main` clean at all times.
- Start every task from a temporary worktree created from `main`.
- Finish coding, verification, and commit(s) inside that worktree.
- Return to `main`, merge the finished worktree branch, then remove the temporary worktree.

## Required Flow

Every task follows this sequence:

1. Inspect the current repo state from the main checkout.
2. Create a temporary branch and `git worktree` from `main`.
3. Do all coding work inside the worktree.
4. Run the required verification inside the worktree.
5. Commit the task result inside the worktree.
6. Return to the main checkout and switch to `main`.
7. Merge the worktree branch into `main`.
8. If the task completed successfully, remove the temporary worktree and delete the temporary branch.

## Guardrails

- Do not skip the worktree step because the task seems small. The default is still to start in a worktree.
- Do not ask the user to re-confirm this mode on each task.
- Do not merge unverified work back into `main`.
- Do not leave temporary worktrees behind after a successful task unless the user explicitly asks to keep them.
- Preserve user changes and do not revert unrelated work.

## Operational Notes

- The worktree branch should be created from `main`, not from the current feature branch.
- Verification should match the task scope, but it must happen before the final merge.
- The final integration step is not complete until the worktree branch is merged into `main`.
- Successful completion means the full lifecycle is closed: worktree created, changes implemented, verification run, commit created, merged into `main`, worktree cleaned up.
