## Skills

- For any change that touches gateway auth, `.env`, secure storage, tokens, passwords, TLS, file upload, native entitlements, packaging, or release-sensitive settings, follow the security rules in this file and [docs/security/secure-development-rules.md](docs/security/secure-development-rules.md).
- For non-trivial implementation work, default to the worktree-first execution flow in this file without asking the user to restate that preference each time.

## Cross-Repo Architecture Chain Maps

When modifying code that crosses repo boundaries (app ↔ bridge ↔ OpenClaw ↔ plugins), consult the corresponding chain map first. Each map documents the full call flow, protocol boundaries, data structures, and known fragile points across all participating repositories.

Required reading before modifying:
- **Task execution**: [chain-map-task-execution.md](docs/architecture/chain-map-task-execution.md) — full path from `sendChatMessage()` through bridge routing, OpenClaw gateway, to plugin artifact export.
- **Artifact lifecycle**: [chain-map-artifact-lifecycle.md](docs/architecture/chain-map-artifact-lifecycle.md) — prepare → execute → export → snapshot → download → sync. Documents the critical path gap where OpenClaw tools save to `~/.openclaw/media/` or `/tmp/` instead of `tasks/<session>/<run>/`.
- **Session recovery**: [chain-map-session-recovery.md](docs/architecture/chain-map-session-recovery.md) — app restart, bridge restart, network interruption, gateway unreachable scenarios and their state machines.
- **Bridge distributed**: [chain-map-bridge-distributed.md](docs/architecture/chain-map-bridge-distributed.md) — primary→edge forwarding topology, session stickiness, VPN transport, hop limits.
- **Overview**: [cross-repo-call-analysis-2026-06-05.md](docs/architecture/cross-repo-call-analysis-2026-06-05.md) — complete cross-repo module relationship map, protocol boundaries, key data structures, and top-10 fragile points.

When any change touches the bridge protocol, artifact paths, session state, or routing/recovery logic:
- Verify the change against each affected chain map.
- If the change introduces a new call path, data field, or protocol behavior, update the corresponding chain map in the same PR.
- Pay special attention to the artifact path gap: OpenClaw tools produce output in `~/.openclaw/media/` and `/tmp/openclaw/` but the export plugin only scans `tasks/<session>/<run>/`. Any feature that adds OpenClaw tool usage must ensure outputs land in the task-scoped directory.

## Default Task Mode

- Default to an isolated `git worktree` for non-trivial tasks. Create the worktree from `main`, do the work there, merge back to `main`, then remove the temporary worktree when done.
- Default to concurrent execution for independent sub-tasks. Keep the main agent on the critical path and use parallel lanes only for bounded side work that does not block the next local step.
- Do not repeatedly ask whether worktree mode or concurrent execution should be used for this repo; treat that as the default unless the user explicitly asks for a different flow.
- Keep the branch/worktree lifecycle explicit: inspect, implement, verify, merge, clean up.

## Backward Compatibility Policy

Default policy:
- `No explicit compatibility requirement -> No backward compatibility`.

Forbidden by default:
- Keeping old and new fields side-by-side without a concrete removal plan.
- Maintaining old and new API shapes at the same time.
- Preserving old execution paths, old runtime lanes, or old provider truth sources.
- Adding or preserving "temporary" fallback/preset backfill/legacy default revival behavior.
- Preserving controller split paths, adapter bypasses, or dual routing logic for convenience.

Allowed only with explicit requirement:
- A compatibility layer is allowed only when explicitly required by user request, baseline docs, ADR, API contract, or migration spec.
- Every allowed compatibility layer must declare owner, scope, exit criteria, and planned removal window.
- PRs/plans must include explicit test coverage for the compatibility scope and its exit behavior.

Review and enforcement:
- When compatibility code is discovered, default action is removal.
- If removal is blocked, the PR/plan must explicitly justify why compatibility is required now.
- "Maybe someone still uses it" is not an acceptable reason without explicit requirement evidence.

Scope boundary:
- Legacy recovery paths explicitly retained by architecture/security baselines (for example secure local persistence legacy recovery) are not auto-deleted, but must not expand into current main flows.

## Fallback and Dead Code Elimination Policy

Forbidden patterns (must be removed on discovery):
- Cascading fallback chains where A → B → C all resolve to the same underlying call with no added logic.
- Methods marked "DEPRECATED" that remain in code. Either remove them or justify with a concrete removal plan + date.
- Dead code paths behind `UnsupportedError` or `throw` guards — the guard is the signal that everything downstream is dead.
- Swallowing catch blocks (`catch (_) {}`) without at least a debug log. Silent error hiding is not allowed.
- Redundant method indirection where method A calls method B which calls method C with no transformation, filtering, or side effects.
- Probing 5+ JSON keys in a cascade for the same field — consolidate to a single well-known schema or document why the schema is loose.

Allowed only with explicit justification:
- Retry/recovery chains for network protocols (document the error categories handled at each level).
- JSON field probing when bridging between loosely-typed external responses and strongly-typed Dart models (document the expected schema and fallback order).
- Process lifecycle escalation (SIGTERM → SIGKILL) as a last resort during shutdown.
- Legitimate null-coalescing chains for configuration defaults with clear precedence order.

Review and enforcement:
- When a fallback chain is discovered, default action is simplification or removal.
- Every retained fallback chain must include a comment explaining WHY each level exists.
- "Just in case" or "defensive programming" is not sufficient justification.

## Refactor Workflow Standard

This section defines the reusable refactor workflow for this repo.
When trigger conditions are met, the workflow is executed by default without additional confirmation prompts.

Normative source:
- Use this section as the single enforcement source for refactor execution rules.
- ADR documents only record decision background and must not introduce conflicting rules.

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

Baseline commands:
- `flutter analyze`
- `flutter test test/app_controller_desktop_runtime_cleanup_test.dart`
- `flutter test test/app_controller_desktop_working_directory_dispatch_test.dart`
- `flutter test test/runtime/external_code_agent_acp_desktop_transport_test.dart`
- `flutter test test/app_controller_desktop_thread_target_cleanup_test.dart`

Cleanup baseline requirements:
- Every "stale code cleanup" task must include an explicit list of removed compatibility layers; wrapper-only/refactor-only changes are insufficient.
- Every cleanup regression report must prove:
  - old truth sources no longer participate in current decisions,
  - current baseline paths still pass after compatibility removal,
  - no new behavior is preserved under `legacy` / `fallback` / `compat` by default.

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
- Assistant conversation runtime must treat signed-out state as disconnected: do not send requests, do not read stale managed bridge secrets, and do not fallback to local ACP endpoints or default managed bridge endpoints.
- Missing managed `BRIDGE_AUTH_TOKEN` means disconnected. Do not fallback from bridge ACP auth to gateway profile tokens.
- Keep the UI unchanged for bridge state-flow fixes unless explicitly requested; adjust runtime readiness, endpoint resolution, and tests instead.
- After svc.plus login and bridge sync, route all provider and gateway execution through the unified managed bridge endpoint `/acp/rpc`. Do not use provider-specific paths or directly construct `/acp-server/*` or `/gateway/*` URLs.
- For a user-initiated gateway connect action, the current form values may be used directly for the immediate handshake. Do not require a secure-store readback for the active request.
- Keep network trust boundaries explicit. Loopback/local mode may use non-TLS intentionally; remote mode must not silently downgrade transport security.
- File and attachment access must be user-driven. Never read or send workspace files implicitly.
- Any new macOS or iOS entitlement must be least-privilege, justified by the feature, and covered by tests or manual verification notes.
- Auth, secret, network, or entitlement changes require `flutter analyze` and relevant Flutter unit/widget tests.

## Testing Rules

- Modify any Flutter UI page, and you must add or update widget tests and golden tests.
- Modify any core business flow, and you must add or update focused Flutter tests under `test/`.
- Modify permission, camera, file picker, notification, WebView, or native page interaction behavior, and you must add or update the nearest existing Flutter regression coverage under `test/`.
- All UI tests must use `Key`-based locators first. Avoid fragile text-only or hierarchy-only selectors unless no Key exists yet.
- Release/* branches must run the current repo-native validation chain from `docs/README_TESTING.md`.
  At minimum for this repo that means `flutter analyze` and `flutter test`.
- New features must follow test first, then implementation, then full regression.
- Keep tests split by module. Do not pile every scenario into one file.
- Golden baseline refreshes require UI review confirmation before updating reference images. Run the actual golden test files that exist in `test/features/**`.
- CI failures must be fixed in tests or implementation. Do not skip the failing check in merge workflows.

See [docs/security/secure-development-rules.md](docs/security/secure-development-rules.md) for the full checklist.
