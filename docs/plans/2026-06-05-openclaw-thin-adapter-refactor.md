# OpenClaw Thin Adapter Refactor Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Reduce `openclaw-multi-session-plugins` from a task/session/event owner to a thin adapter while preserving XWorkmate task awareness, artifact isolation, and OpenClaw Gateway E2E behavior.

**Architecture:** `openclaw.svc.plus` is upstream and read-only. XWorkmate must carry typed metadata through App -> Bridge -> Plugin gateway methods, persist the app/OpenClaw session mapping in `SessionEntry.pluginExtensions` through existing OpenClaw runtime APIs, and query OpenClaw native task records instead of custom task stores. Bridge remains the App protocol adapter and event normalizer, not a task/session source of truth.

**Tech Stack:** Dart/Flutter (`xworkmate-app`), Go (`xworkmate-bridge`), TypeScript/Vitest (`openclaw-multi-session-plugins`), OpenClaw 2026.6.1 runtime APIs as read-only upstream.

---

## Hard Constraints

- Do not modify `/Users/shenlan/workspaces/cloud-neutral-toolkit/openclaw.svc.plus`.
- Do not rely on prompt text parsing for metadata.
- Do not use `agent:main:${appThreadKey}` or `replace("agent:main:", "")` as the new-path session mapping.
- Legacy string derivation is allowed only as one-time migration that writes a durable mapping.
- Do not restore plugin-owned task DB, session DB, or event bus.
- Validation must reference `docs/cases/`, especially `docs/cases/openclaw-gateway-e2e-regression/README.md`.

## Source-of-Truth Decision

- Task terminal state: OpenClaw native task registry when available.
- Transcript/progress events: OpenClaw native transcript/runtime events, transported through Bridge/App SSE if needed.
- Mapping truth: `SessionEntry.pluginExtensions[PLUGIN_ID]["xworkmate.sessionMapping"]`.
- Artifact expected dirs: typed xworkmate metadata, mirrored into mapping and explicit artifact gateway params.

Because upstream `chat.send` rejects unknown fields and upstream `session_start` does not carry xworkmate metadata, Bridge must call a plugin gateway method before `chat.send` to upsert mapping and prepare artifacts. That method is the local adapter seam that avoids modifying OpenClaw.

## Target Metadata Shape

```ts
type XWorkmateTaskMetadataV1 = {
  schemaVersion: 1;
  appThreadKey: string;
  openclawSessionKey?: string;
  expectedArtifactDirs: string[];
  requestId?: string;
  externalTaskId?: string;
  createdAt: string;
};

type XWorkmateSessionMappingV1 = {
  schemaVersion: 1;
  appThreadKey: string;
  openclawSessionKey: string;
  expectedArtifactDirs: string[];
  createdAt: string;
  updatedAt: string;
  source: "session_start" | "bridge_prepare" | "legacy_migration";
  legacyDerived?: boolean;
};
```

## Task 1: Plugin Contract Tests for Durable Session Mapping

**Files:**
- Modify: `/Users/shenlan/workspaces/cloud-neutral-toolkit/openclaw-multi-session-plugins/src/taskState.ts`
- Modify: `/Users/shenlan/workspaces/cloud-neutral-toolkit/openclaw-multi-session-plugins/index.ts`
- Test: `/Users/shenlan/workspaces/cloud-neutral-toolkit/openclaw-multi-session-plugins/src/taskState.test.ts`

**Step 1: Write failing tests**

Add tests for:

- `recordXWorkmateSessionMapping` requires typed `appThreadKey`.
- `openclawSessionKey` is taken from trusted gateway params/session scope, not derived from `appThreadKey`.
- Mapping is written to `SessionEntry.pluginExtensions`.
- Idempotent same mapping updates `updatedAt`.
- Conflicting existing mapping fails closed.
- Legacy derivation, if needed, writes `legacyDerived: true` and persists the mapping.

**Step 2: Run failing test**

```bash
cd /Users/shenlan/workspaces/cloud-neutral-toolkit/openclaw-multi-session-plugins
pnpm test src/taskState.test.ts
```

Expected: FAIL until mapping helpers exist.

**Step 3: Implement minimal plugin mapping helper**

Implement helpers in `src/taskState.ts`:

- `normalizeXWorkmateTaskMetadataV1(input)`
- `normalizeExpectedArtifactDirs(input)`
- `upsertXWorkmateSessionMapping(api, metadata, openclawSessionKey, source)`
- `readXWorkmateSessionMapping(api, lookup)`

Use `api.runtime.agent.session.getSessionEntry` and `api.runtime.agent.session.patchSessionEntry` if available. If runtime patch is unavailable, return structured `mapping_not_found` / `invalid_lookup`; do not silently fall back to an in-memory map.

**Step 4: Run tests**

```bash
pnpm test src/taskState.test.ts
pnpm typecheck
```

Expected: PASS.

## Task 2: Plugin Gateway Method for Mapping + Artifact Prepare

**Files:**
- Modify: `/Users/shenlan/workspaces/cloud-neutral-toolkit/openclaw-multi-session-plugins/index.ts`
- Modify: `/Users/shenlan/workspaces/cloud-neutral-toolkit/openclaw-multi-session-plugins/src/exportArtifacts.ts`
- Test: `/Users/shenlan/workspaces/cloud-neutral-toolkit/openclaw-multi-session-plugins/src/exportArtifacts.test.ts`

**Step 1: Write failing tests**

Add/extend tests for a new gateway method, preferably `xworkmate.session.prepare`, that:

- accepts `{ schemaVersion, appThreadKey, openclawSessionKey, expectedArtifactDirs, runId?, requestId? }`;
- rejects absolute paths and `..` in `expectedArtifactDirs`;
- preserves expected dirs even when directories do not exist yet;
- calls artifact prepare before agent execution;
- returns mapping and artifact directory status.

**Step 2: Run failing test**

```bash
pnpm test src/exportArtifacts.test.ts
```

Expected: FAIL until gateway method is registered.

**Step 3: Implement the method**

In `index.ts`, register `xworkmate.session.prepare`. It should:

- call the mapping helper from Task 1;
- call `prepareXWorkmateArtifacts`;
- return `{ ok: true, mapping, artifactScope, artifactDirectory, expectedArtifactDirs }`.

Keep `xworkmate.artifacts.prepare/export/collect-and-snapshot` as thin artifact operations. Remove in-memory `createXWorkmateTaskStore()` as a required source of truth.

**Step 4: Run plugin suite**

```bash
pnpm test
pnpm typecheck
pnpm pack:check
```

Expected: PASS.

## Task 3: Plugin `xworkmate.tasks.get` Uses Native Task Registry

**Files:**
- Modify: `/Users/shenlan/workspaces/cloud-neutral-toolkit/openclaw-multi-session-plugins/src/taskState.ts`
- Modify: `/Users/shenlan/workspaces/cloud-neutral-toolkit/openclaw-multi-session-plugins/index.ts`
- Test: `/Users/shenlan/workspaces/cloud-neutral-toolkit/openclaw-multi-session-plugins/src/taskState.test.ts`

**Step 1: Write failing tests**

Cover inputs:

```ts
{
  taskId?: string;
  runId?: string;
  appThreadKey?: string;
  openclawSessionKey?: string;
  includeArtifacts?: boolean;
  includeEvents?: boolean;
}
```

Expected structured errors:

- `mapping_not_found`
- `task_not_found`
- `no_native_task_record`
- `conflict`
- `invalid_lookup`

**Step 2: Implement lookup**

Rules:

- `appThreadKey -> openclawSessionKey` must read pluginExtensions mapping.
- `runId/taskId` must query `api.runtime.tasks.runs.bindSession({ sessionKey }).resolve/get/list/findLatest`.
- If no native task exists, return `no_native_task_record`; do not infer success from artifacts.
- If `includeArtifacts`, call export/list resolver and include artifact dir status plus expected dirs.

**Step 3: Run plugin checks**

```bash
pnpm test src/taskState.test.ts src/exportArtifacts.test.ts
pnpm typecheck
```

Expected: PASS.

## Task 4: Bridge Sends Typed Metadata and Stops Session String Derivation

**Files:**
- Modify: `/Users/shenlan/workspaces/cloud-neutral-toolkit/xworkmate-bridge/internal/acp/orchestrator.go`
- Modify: `/Users/shenlan/workspaces/cloud-neutral-toolkit/xworkmate-bridge/internal/acp/rpc_handler.go`
- Modify: `/Users/shenlan/workspaces/cloud-neutral-toolkit/xworkmate-bridge/internal/acp/openclaw_thread_session_mapper.go`
- Modify: `/Users/shenlan/workspaces/cloud-neutral-toolkit/xworkmate-bridge/internal/acp/types.go`
- Test: `/Users/shenlan/workspaces/cloud-neutral-toolkit/xworkmate-bridge/internal/acp/web_contract_test.go`

**Step 1: Write failing bridge tests**

Extend the case from `docs/cases/openclaw-gateway-e2e-regression/README.md`:

- five concurrent OpenClaw requests remain running/completed, not queued;
- Bridge calls `xworkmate.session.prepare` before `chat.send`;
- request to plugin includes `appThreadKey`, `openclawSessionKey`, `expectedArtifactDirs`;
- no code path calls `ThreadSessionMapper.OpenClawSessionID` for the new path;
- events include `appThreadKey`, `openclawSessionKey`, `runId/taskId` where available.

**Step 2: Run failing bridge test**

```bash
cd /Users/shenlan/workspaces/cloud-neutral-toolkit/xworkmate-bridge
go test ./internal/acp -run TestHTTPHandlerGatewayOpenClawHandlesFiveConcurrentE2ECases -count=1
```

Expected: FAIL until prepare call and metadata are wired.

**Step 3: Implement Bridge changes**

In `startOpenClawGatewayTask`:

- validate and normalize `expectedArtifactDirs`;
- compute or receive the actual OpenClaw session key from the Bridge request path, but do not use legacy string replacement;
- call plugin `xworkmate.session.prepare` before `chat.send`;
- pass `expectedArtifactDirs` to artifact export/list as explicit typed params;
- treat plugin mapping conflicts as fail-closed.

In `xworkmate.tasks.get` handler:

- forward lookup to plugin/native path;
- stop reconstructing `OpenClawTaskRecord` from `artifactScope` as a source of truth;
- use native reconciliation on reconnect.

**Step 4: Run bridge checks**

```bash
go test ./internal/acp -count=1
go test ./...
go vet ./...
go build ./...
```

Expected: PASS.

## Task 5: App Typed Lookup and Recovery Contract

**Files:**
- Modify: `/Users/shenlan/workspaces/cloud-neutral-toolkit/xworkmate-app/lib/runtime/runtime_models_runtime_payloads.dart`
- Modify: `/Users/shenlan/workspaces/cloud-neutral-toolkit/xworkmate-app/lib/runtime/go_task_service_client.dart`
- Modify: `/Users/shenlan/workspaces/cloud-neutral-toolkit/xworkmate-app/lib/runtime/external_code_agent_acp_desktop_transport.dart`
- Modify: `/Users/shenlan/workspaces/cloud-neutral-toolkit/xworkmate-app/lib/app/app_controller_desktop_thread_actions.dart`
- Test: `/Users/shenlan/workspaces/cloud-neutral-toolkit/xworkmate-app/test/runtime/assistant_execution_target_test.dart`
- Test: `/Users/shenlan/workspaces/cloud-neutral-toolkit/xworkmate-app/test/runtime/gateway_acp_client_auth_test.dart`
- Test: `/Users/shenlan/workspaces/cloud-neutral-toolkit/xworkmate-app/test/runtime/desktop_thread_artifact_service_test.dart`

**Step 1: Write failing App tests**

Use `docs/cases/openclaw-gateway-e2e-regression/README.md` as the fixture source:

- five canonical prompts submit with `appThreadKey` and `expectedArtifactDirs`;
- `xworkmate.tasks.get` params include `appThreadKey`, `openclawSessionKey` when known, `runId`, and include flags;
- `no_native_task_record` is rendered as an explicit recovery state, not mistaken for success;
- artifact sidebar keeps no-artifact empty state and blocks stale files.

**Step 2: Run failing tests**

```bash
cd /Users/shenlan/workspaces/cloud-neutral-toolkit/xworkmate-app
flutter test test/runtime/assistant_execution_target_test.dart
flutter test test/runtime/gateway_acp_client_auth_test.dart
flutter test test/runtime/desktop_thread_artifact_service_test.dart
```

Expected: FAIL until typed lookup fields are added.

**Step 3: Implement App changes**

- Add `appThreadKey`, `openclawSessionKey`, and `expectedArtifactDirs` to task association / task-get DTOs.
- Keep current metadata generation, but rename/extend the contract so `appThreadKey` is explicit.
- Preserve directories even if not present locally.
- Do not read or persist secrets differently.

**Step 4: Run targeted App checks**

```bash
flutter analyze
flutter test test/runtime/assistant_execution_target_test.dart
flutter test test/runtime/gateway_acp_client_auth_test.dart
flutter test test/runtime/desktop_thread_artifact_service_test.dart
flutter test test/features/assistant/assistant_artifact_sidebar_test.dart
```

Expected: PASS.

## Task 6: Remove/Downgrade Custom State Centers

**Files:**
- Modify: `/Users/shenlan/workspaces/cloud-neutral-toolkit/openclaw-multi-session-plugins/src/taskState.ts`
- Modify: `/Users/shenlan/workspaces/cloud-neutral-toolkit/xworkmate-bridge/internal/acp/openclaw_async_tasks.go`
- Modify: `/Users/shenlan/workspaces/cloud-neutral-toolkit/xworkmate-bridge/internal/acp/types.go`
- Modify: `/Users/shenlan/workspaces/cloud-neutral-toolkit/xworkmate-bridge/internal/acp/rpc_handler.go`

**Step 1: Delete dead primary state paths**

Remove or downgrade:

- plugin in-memory task/session maps as truth;
- Bridge `OpenClawTaskRecord` terminal authority;
- Bridge task reassociation from `artifactScope`;
- session key string derivation as primary route.

Retain only transport/reconciliation caches that have clear owner, scope, and invalidation rules.

**Step 2: Static guard**

Run:

```bash
rg -n "agent:main:\\$|replace\\(|ThreadSessionMapper|createXWorkmateTaskStore|sessionMappingsBy|records = new Map|bridgeAgents" \
  /Users/shenlan/workspaces/cloud-neutral-toolkit/openclaw-multi-session-plugins \
  /Users/shenlan/workspaces/cloud-neutral-toolkit/xworkmate-bridge \
  /Users/shenlan/workspaces/cloud-neutral-toolkit/xworkmate-app
```

Expected: only documented migration or tests remain.

## Task 7: Docs and Case Updates

**Files:**
- Modify: `/Users/shenlan/workspaces/cloud-neutral-toolkit/xworkmate-app/docs/ai-context/chain-map.md`
- Modify: `/Users/shenlan/workspaces/cloud-neutral-toolkit/xworkmate-app/docs/architecture/chain-map-task-execution.md`
- Modify: `/Users/shenlan/workspaces/cloud-neutral-toolkit/xworkmate-app/docs/architecture/chain-map-artifact-lifecycle.md`
- Modify: `/Users/shenlan/workspaces/cloud-neutral-toolkit/xworkmate-app/docs/cases/openclaw-gateway-e2e-regression/README.md`

**Step 1: Update source-of-truth docs**

Document:

- mapping stored in `SessionEntry.pluginExtensions`;
- Bridge pre-chat `xworkmate.session.prepare`;
- expected dirs typed propagation;
- native task-registry terminal state;
- App SSE as transport only.

**Step 2: Update case acceptance**

Add explicit checks to the OpenClaw E2E case:

- pluginExtensions contains `draft:*` <-> `agent:main:draft:*`;
- `expectedArtifactDirs` visible in plugin task output;
- `xworkmate.tasks.get` returns native task or `no_native_task_record`;
- no stale artifact display.

## Task 8: Full Regression and Manual Verification

**Automated commands:**

```bash
# openclaw-multi-session-plugins
cd /Users/shenlan/workspaces/cloud-neutral-toolkit/openclaw-multi-session-plugins
pnpm test
pnpm typecheck
pnpm pack:check

# xworkmate-bridge
cd /Users/shenlan/workspaces/cloud-neutral-toolkit/xworkmate-bridge
go test ./...
go vet ./...
go build ./...

# xworkmate-app
cd /Users/shenlan/workspaces/cloud-neutral-toolkit/xworkmate-app
flutter analyze
flutter test test/runtime/assistant_execution_target_test.dart
flutter test test/runtime/gateway_acp_client_auth_test.dart
flutter test test/runtime/desktop_thread_artifact_service_test.dart
flutter test test/features/assistant/assistant_artifact_sidebar_test.dart
flutter test
```

**Manual cases from `docs/cases/`:**

- `OPENCLAW-E2E-001` through `OPENCLAW-E2E-005` from `docs/cases/openclaw-gateway-e2e-regression/README.md`.
- `MANUAL-GATEWAY-001` through `MANUAL-GATEWAY-004` from `docs/cases/core-integration-manual-cases.md`.
- `MANUAL-THREAD-002` for cross-thread state/artifact isolation.

**Acceptance evidence to record:**

- App thread path: `$HOME/.xworkmate/threads/draft-1780636411666238-3`.
- `appThreadKey`: `draft:1780636411666238-3`.
- `openclawSessionKey`: `agent:main:draft:1780636411666238-3`.
- Plugin mapping exists in `SessionEntry.pluginExtensions`.
- `expectedArtifactDirs` survives App -> Bridge -> Plugin -> artifact resolver.
- No Bridge primary path uses string replace/prefix derivation.
- Plugin has no primary custom task/session/event store.

## Rollback Point

Keep the rollback boundary after Task 4:

- If Plugin mapping works but Bridge cannot safely pre-call `xworkmate.session.prepare`, stop before App rollout.
- Revert Bridge/App protocol changes while retaining plugin tests and docs.
- Do not introduce OpenClaw upstream patch as a workaround.

## Residual Risks

- If ordinary OpenClaw `chat.send` does not create native task records, `xworkmate.tasks.get` must return `no_native_task_record` until Bridge uses an existing native task-producing OpenClaw path or a native registry mirror API exposed by the read-only upstream.
- Because upstream `session_start` has no typed xworkmate metadata, `source: "session_start"` cannot be the main new-path source without upstream changes. In the no-upstream-change plan, use `source: "bridge_prepare"` for current new writes and reserve `session_start` only for future upstream support.
- The plugin package may need dependency alignment with OpenClaw 2026.6.1 types before `pnpm typecheck` is stable.
