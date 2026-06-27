# Cases 00–05 Gateway Turn Stability Acceptance Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 在本机 all-in-one 运行态中完成 `docs/cases/00–05` 的真实任务验收，修复发现的 Gateway Turn 稳定性缺口，并把全过程证据回写到 Case 06。

**Architecture:** 以 Case 06 的 App → Bridge → multi-session plugin → OpenClaw gateway 四层链路为主线。先验证安装与运行态，再以定向测试锁住取消、超时、断线与 pending 清理语义，最后通过真实 Bridge 请求执行五类任务并核对状态、Artifact、重复执行与失败收口。

**Tech Stack:** Flutter/Dart、Go、OpenClaw gateway、JSON-RPC/SSE、macOS launchd、GitHub Actions。

---

### Task 1: Baseline and progress ledger

**Files:**
- Modify: `docs/cases/06-gateway-turn-stability-and-robustness.md`
- Create: `docs/plans/2026-06-27-cases-00-05-gateway-turn-acceptance.md`

**Steps:**
1. Capture branch, commit, dirty files, installed services, `/api/ping`, gateway plugin provenance, and Case 00 prerequisites.
2. Add a timestamped execution ledger to Case 06 without storing API keys or auth tokens.
3. Record each later command by outcome and evidence, not by secrets-bearing command line.

### Task 2: Local all-in-one deployment

**Files:**
- Modify only when a reproducible installer/runtime defect is found; keep each fix in its owning repository.
- Modify: `docs/cases/06-gateway-turn-stability-and-robustness.md`

**Steps:**
1. Inspect the hosted bootstrap before execution and verify its final origin/redirect.
2. Run the installer with `DEEPSEEK_API_KEY`, `NVIDIA_API_KEY`, and `OLLAMA_API_KEY` supplied only through the child-process environment.
3. Retry transient download/network failures with bounded backoff.
4. Verify Bridge `/api/ping.commit`, gateway port `18789`, plugin stable path/provenance, and `xworkmate.session.prepare` behavior.

### Task 3: Gateway Turn regression implementation

**Files:**
- Modify: `lib/app/app_controller_desktop_runtime_helpers.dart`
- Modify: `lib/app/app_controller_desktop_thread_actions.dart`
- Test: `test/runtime/assistant_execution_target_test.dart`
- Test other runtime files only when the failure belongs there.

**Steps:**
1. Add failing tests for bounded `ACP_HTTP_CONNECTION_CLOSED` polling recovery and retry exhaustion.
2. Run the focused test and confirm the new assertion fails before implementation where practicable.
3. Implement the smallest change that preserves pending during bounded retry and deterministically reaches terminal state after exhaustion.
4. Run `flutter test test/runtime/assistant_execution_target_test.dart` and related gateway runtime tests.
5. Run `scripts/ci/run_layered_tests.sh` to match the repository CI path.

### Task 4: Cases 00–05 live acceptance

**Files:**
- Modify: `docs/cases/06-gateway-turn-stability-and-robustness.md`

**Steps:**
1. Verify Case 00 connectivity and error behavior against the local Bridge/Gateway runtime.
2. Execute Case 01 three times; validate Markdown structure, terminal status, non-empty Artifact, and isolation.
3. Execute Cases 02–05 with the documented prompts and a deterministic local test image for Case 02.
4. Exercise cancellation, invalid auth/unreachable endpoint, repeated runs, exact item/page counts, and Artifact retrieval where supported.
5. Record run IDs, durations, terminal status, artifact paths/counts, and any scoped deviations.

### Task 5: Full verification and delivery

**Files:**
- Modify: `docs/cases/06-gateway-turn-stability-and-robustness.md`

**Steps:**
1. Run formatting/analyzer and the full relevant Flutter suite; rerun failed tests individually to distinguish deterministic regressions from flakes.
2. Review the complete diff and confirm no credential values or generated secrets are tracked.
3. Commit cohesive changes on `main` with explicit messages.
4. Push to `origin/main`; retry transient push failures with bounded exponential backoff.
5. Verify the newest GitHub Actions run(s) and append final acceptance status/blockers to Case 06.
