## Skills

- Use `xworkmate-acceptance` before claiming build, packaging, installation, or release readiness for this repo.
- For any change that touches gateway auth, `.env`, secure storage, tokens, passwords, TLS, file upload, native entitlements, packaging, or release-sensitive settings, follow the security rules in this file and [docs/security/secure-development-rules.md](/Users/shenlan/workspaces/cloud-neutral-toolkit/XWorkmate.svc.plus/docs/security/secure-development-rules.md).
- For non-trivial implementation work, default to the worktree-first execution flow in this file without asking the user to restate that preference each time.

## Default Task Mode

- Default to an isolated `git worktree` for non-trivial tasks. Create the worktree from `main`, do the work there, merge back to `main`, then remove the temporary worktree when done.
- Default to concurrent execution for independent sub-tasks. Keep the main agent on the critical path and use parallel lanes only for bounded side work that does not block the next local step.
- Do not repeatedly ask whether worktree mode or concurrent execution should be used for this repo; treat that as the default unless the user explicitly asks for a different flow.
- Keep the branch/worktree lifecycle explicit: inspect, implement, verify, merge, clean up.

## Refactor Workflow Standard

This section defines the reusable refactor workflow for this repo.
When trigger conditions are met, the workflow is executed by default without additional confirmation prompts.

### Workflow Composition

The standard combines:
- Orchestrator-style execution (main lane owns critical path, parallel lanes handle bounded side work)
- TDD refactor rhythm (`RED -> GREEN -> REFACTOR -> REGRESSION`)
- Flutter assistant/composer split guidance for oversized UI closures
- `xworkmate-lean-tdd-ddd-lite` as the primary architecture and verification constraint

### Trigger Conditions (重构触发条件)

Hard triggers (execute immediately):
- A single business file is larger than 800 lines, or close to 1000 lines.
- A business closure spreads across multiple `helpers`/utility files without clear ownership.
- A key flow regression fails and root cause points to structural coupling.
- The same business change requires repeated cross-layer edits (`lib/app`, `lib/runtime`, `lib/features`) in at least two consecutive change rounds.
- Security-sensitive changes cause controller/orchestrator responsibilities to mix with deep business logic.

Soft triggers (recommended execution):
- PR review flags unclear ownership, duplicated logic, or low testability.
- A bug fix requires simultaneous edits across 3+ files for one business behavior.

### Triggered Execution Flow (触发后执行流程)

`Phase 0 - Closure Selection`
- Pick one smallest business closure as the implementation unit.
- Define explicit in-scope/out-of-scope boundaries before writing code.

`Phase 1 - RED`
- Add or expand tests first for current behavior and regression points.
- Confirm failing expectation matches intended behavior change.

`Phase 2 - GREEN`
- Apply the minimum code change that makes the new/updated tests pass.
- Avoid introducing extra abstraction layers unless complexity requires it.

`Phase 3 - REFACTOR`
- Immediately refine names, dependency directions, and closure boundaries.
- Keep domain logic pure; keep orchestration in application/controller layers.

`Phase 4 - REGRESSION`
- Run targeted suites and required quality checks.
- Run broader regression when the closure touches shared execution paths.

`Phase 5 - SECURITY/ACCEPTANCE`
- If change scope touches auth/secrets/network/entitlements/release-sensitive settings, apply security baseline checks.
- Before any build/package/install/release readiness claim, run `xworkmate-acceptance`.

Baseline commands:
- `flutter analyze`
- `flutter test test/runtime/app_controller_assistant_flow_test.dart`
- `flutter test test/runtime/code_agent_node_orchestrator_test.dart`
- `flutter test test/runtime/app_controller_thread_skills_test.dart`
- `flutter test test/quality/wave1_file_size_guard_test.dart`

### Execution Roles

- Main lane:
  - Owns closure decisions, implementation, and merge readiness.
  - Resolves any blockers that affect immediate next steps.
- Parallel lanes:
  - Run bounded verification, diagnostics, documentation, and non-blocking side checks.
  - Must not override main-lane code inspection and test evidence.

### Required Deliverables (触发执行后的必交付物)

Each triggered refactor must include:
- Test list: added/updated tests and covered behavior.
- Refactor record: closure boundary, key edits, risks, rollback point.
- Regression record: executed commands and pass/fail outcomes.
- Residual risk note: uncovered risk and next recommended action.

### Then Tasks (当前仓库优先任务包)

- `T1 (P0)` Align file-size guard targets with real implementation-bearing files (not only thin export entry files).
- `T2 (P0)` Split oversized assistant/composer closure while preserving behavior and key-flow tests.
- `T3 (P1)` Shrink oversized desktop/runtime controller closures with explicit ownership boundaries.
- `T4 (P1)` Eliminate unowned helper sprawl; keep helper code business-closure-owned.
- `T5 (P0/P1)` Run regression and security/acceptance gates and document closure-level outcomes.

### Done Criteria

A refactor task is complete only when:
- Closure ownership is clear and readable end-to-end.
- Domain logic remains pure and deterministic.
- Key `task-to-agent-to-result` flows are verified.
- Immediate refactor pass is completed after behavior verification.
- No new unowned helpers/utilities are introduced.
- Security/release checks are executed when trigger scope requires them.

## Security Rules

- `.env` is only a development/test prefill source for Settings -> Integrations -> Gateway. Do not hardcode `.env` values into source code. Do not auto-persist them into settings. Do not auto-connect from them.
- Secrets must not be committed, logged, screenshot-exposed, or stored in `SharedPreferences`. Use secure storage for persisted secrets.
- For a user-initiated gateway connect action, the current form values may be used directly for the immediate handshake. Do not require a secure-store readback for the active request.
- Keep network trust boundaries explicit. Loopback/local mode may use non-TLS intentionally; remote mode must not silently downgrade transport security.
- File and attachment access must be user-driven. Never read or send workspace files implicitly.
- Any new macOS or iOS entitlement must be least-privilege, justified by the feature, and covered by tests or manual verification notes.
- Auth, secret, network, or entitlement changes require `flutter analyze`, relevant unit/widget tests, and serial device-run integration tests when integration coverage is needed.

See [docs/security/secure-development-rules.md](/Users/shenlan/workspaces/cloud-neutral-toolkit/XWorkmate.svc.plus/docs/security/secure-development-rules.md) for the full checklist.
