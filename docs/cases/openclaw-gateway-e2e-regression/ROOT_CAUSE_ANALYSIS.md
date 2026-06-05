# Root Cause Analysis & Fix: "openclaw returned partial artifacts without required final deliverables"

## 四层调用链

```
XWorkmate App (Flutter/Dart)
  └─ xworkmate-bridge (Go)           ← ACP JSON-RPC / SSE proxy
       └─ openclaw-multi-session-plugins (TypeScript)  ← artifact scope 管理
            └─ OpenClaw Gateway Runtime (127.0.0.1:18789)  ← AI agent 执行
```

每个层在 artifact 交付链中承担不同职责。缺陷分布在所有四层。

---

## Fix 0 [P0 — Plugin 层] OpenClaw agent 写入路径与 artifact scope 不匹配

**文件**: `src/exportArtifacts.ts`
**函数**: `exportXWorkmateArtifacts()`
**行号**: 238-259

**问题**：`exportXWorkmateArtifacts()` 只扫描 `tasks/{sessionKey}/{runId}/` scope 目录（由 `resolveScopeRoot()` 计算）。但 OpenClaw agent 执行时的默认工作目录是 workspace 根（`~/.openclaw/workspace`），agent 自然将 PNG/PDF/视频写入 `assets/images/`、`reports/`、`video/` 等 workspace 根路径，而非 `tasks/{sessionKey}/{runId}/` 子目录。

**证据**：测试用例 `"does not adopt workspace root files even with a current-run timestamp"`（行 334-352）和 `"does not adopt same-thread delivery files when the prepared task scope is empty"`（行 459-517）明确验证了 workspace 根文件和 thread 目录下的文件 **不会被** 纳入 artifact scope。但 E2E prompt 中 agent 大概率将输出写入 workspace 相对路径 — 这些文件对 Plugin 完全不可见。

**修复**：在 `exportXWorkmateArtifacts()` 中新增一个扫描源——当 scope 目录为空时，扫描 workspace 根下的指定子目录（由 `expectedArtifactDirs` 参数指定）：

```typescript
// 行 256 candidates = scopedCandidates 之后插入
const expectedDirs = safeStringList(params.expectedArtifactDirs);
if (candidates.length === 0 && expectedDirs.length > 0) {
  for (const dir of expectedDirs) {
    const dirPath = path.join(workspaceRoot, safeInputRelativePath(dir, "expectedArtifactDir"));
    if (await directoryExists(dirPath)) {
      const dirCandidates = await collectCandidates({
        scanRoot: dirPath,
        relativeRoot: workspaceRoot,
        sinceUnixMs,
        warnSkippedSymlinks: true,
        warnings,
        ignoreRules: await loadArtifactIgnoreRules(dirPath, warnings),
      });
      for (const c of dirCandidates) {
        candidates.push(c);
      }
    }
  }
}
```

**Bridge 侧配合**：在 ACP `session.start` 请求参数中新增 `expectedArtifactDirs: ["assets/images", "reports", "video"]`，由 Bridge 透传给 Plugin。

---

## Fix 1 [P0 — App 层] `_recoveredResultFromTaskSnapshot` 引用相等 Bug

**文件**: `lib/runtime/external_code_agent_acp_desktop_transport.dart`
**函数**: `_recoveredResultFromTaskSnapshot()`
**行号**: 403-407

**当前代码**:
```dart
final artifactRecord = _castMap(snapshot['artifacts']);
final artifactItems = artifactRecord['items'];
if (artifactItems is List && result['artifacts'] == artifactRecord) {  // ← Dart == Map 是引用相等
  result['artifacts'] = artifactItems;
}
```

**问题**: `_castMap` 对 `Map<String, dynamic>` 返回自身引用；对泛型 `Map` 调用 `.cast<String, dynamic>()` 创建新对象。经过 `..._castMap(snapshot['result']), ...snapshot` 解构后，`result['artifacts']` 与 `_castMap(snapshot['artifacts'])` 不可能是同一引用 → 条件永假 → 产物丢弃。

**修复**（用 Edit 直接改）:
```dart
final artifactRecord = _castMap(snapshot['artifacts']);
final artifactItems = artifactRecord['items'];
if (artifactItems is List && artifactItems.isNotEmpty) {
  result['artifacts'] = List<Map<String, dynamic>>.from(artifactItems);
} else if (result['artifacts'] is Map) {
  final nestedArtifacts = _castMap(result['artifacts']);
  final nestedItems = nestedArtifacts['items'];
  if (nestedItems is List && nestedItems.isNotEmpty) {
    result['artifacts'] = List<Map<String, dynamic>>.from(nestedItems);
  }
}
```

---

## Fix 2 [P1 — App 层] `_recoverTaskResultAfterStreamClosure` completed 状态竞态

**文件**: `lib/runtime/external_code_agent_acp_desktop_transport.dart`
**函数**: `_recoverTaskResultAfterStreamClosure()`
**行号**: 252-279

**问题**: `status: 'completed'` 不等于产物已写入注册表。OpenClaw Gateway 先标记 status→completed，后异步写入 artifact registry。轮询在此刻拿到空产物快照。

**修复**: 在行 267 `final result = _recoveredResultFromTaskSnapshot(snapshot)` 之后插入产物非空检查：

```dart
final result = _recoveredResultFromTaskSnapshot(snapshot);
// 新增：completed 状态下产物为空时延后重试
final resultArtifacts = _castMap(result['artifacts']);
final artifactItems = resultArtifacts['items'] ?? resultArtifacts;
final hasArtifacts = result.isNotEmpty &&
    (artifactItems is List && artifactItems.isNotEmpty ||
     result['artifacts'] is List && (result['artifacts'] as List).isNotEmpty);
if (!hasArtifacts && status == 'completed' && attempt < attempts - 1) {
  continue;
}
// 新增结束
if (result.isNotEmpty) {
  return goTaskServiceResultFromAcpResponse(...);
}
```

---

## Fix 3 [P1 — App 层] `persistGoTaskArtifactsForSessionInternal` 产物完整性从不验证

**文件**: `lib/app/app_controller_desktop_runtime_helpers.dart`
**函数**: `persistGoTaskArtifactsForSessionInternal()`
**行号**: 876-882

**问题**: syncStatus 判断 `wroteArtifact ? (failedArtifact || skippedArtifact ? 'partial' : 'synced')` 不验证该有的文件齐不齐。`requiredArtifactExtensions` 字段从 Bridge 传入但从不使用。

**修复** — 在 syncStatus 赋值处（行 876）替换：

```dart
final thread = taskThreadForSessionInternal(normalizedSessionKey);
final requiredExts = thread?.lifecycleState.openClawTaskAssociation
    ?.requiredArtifactExtensions ?? const <String>[];
final missingRequired = requiredExts.where((ext) {
  return !currentTaskArtifactPaths.any(
    (p) => p.toLowerCase().endsWith(ext.toLowerCase()),
  );
}).toList(growable: false);

final syncStatus = wroteArtifact
    ? (failedArtifact || skippedArtifact || missingRequired.isNotEmpty
        ? 'partial'
        : 'synced')
    : failedArtifact
    ? 'download-failed'
    : rejectedArtifact
    ? 'no-exported-artifacts'
    : 'no-artifacts';
```

---

## Fix 4 [P2 — App 层] `_artifactBytesResultInternal` localhost 产物下载被阻止

**文件**: `lib/app/app_controller_desktop_runtime_helpers.dart`
**函数**: `_artifactBytesResultInternal()`
**行号**: 917-924

**修复**:
```dart
final bridgeHost = bridgeEndpoint?.host.trim().toLowerCase() ?? '';
final downloadHost = uri.host.trim().toLowerCase();
final isLoopback = downloadHost == '127.0.0.1' ||
    downloadHost == 'localhost' ||
    downloadHost == '::1';
final sameBridgeHost = bridgeEndpoint != null &&
    (downloadHost == bridgeHost || isLoopback);
if (!sameBridgeHost) {
  return const _ArtifactBytesResult.skipped();
}
```

---

## Fix 5 [P2 — App 层] `pollOpenClawTaskAssociationInternal` 长任务产物完整性检查

**文件**: `lib/app/app_controller_desktop_thread_actions.dart`
**函数**: `pollOpenClawTaskAssociationInternal()`
**行号**: 786-791

**修复**:
```dart
if (aiGatewayPendingSessionKeysInternal.contains(sessionKey)) {
  final hasRequiredExts = current.requiredArtifactExtensions.isNotEmpty;
  final hasEnoughArtifacts = !hasRequiredExts ||
      current.requiredArtifactExtensions.every((ext) {
        return result.artifacts.any(
          (a) => a.relativePath.toLowerCase().endsWith(ext.toLowerCase()),
        );
      });
  if (!hasEnoughArtifacts && attempt < maxAttempts - 1) {
    continue;
  }
  await applyGatewayChatResultInternal(
    sessionKey: sessionKey, target: target, result: result,
  );
}
```

---

## Fix 6 [P1 — Plugin 层] `exportXWorkmateArtifacts` scope 创建与 agent 文件写入时序

**文件**: `src/exportArtifacts.ts`
**函数**: `exportXWorkmateArtifacts()`
**行号**: 242-258

**问题**: `prepareXWorkmateArtifacts()` 创建 scope 目录，但 OpenClaw agent 可能在此调用之前就已开始写入文件。当 agent 首次写入到 scope 路径时目录尚不存在 → agent 可能回退写入到 workspace 根 → 文件不在 scope 内。

**修复**: 在 Bridge 调用链路中，确保 `prepareXWorkmateArtifacts()` 始终在 agent 执行前被调用。在 `bridgeAgents.ts` 的 `runXWorkmateBridgeAgents()` 中（行 31-35）已调用 prepare，但 `exportArtifacts.ts` 的 `exportXWorkmateArtifacts()` 可能被独立调用（绕过 bridgeAgents）。需要在 Gateway 侧接入点确保 prepare 必先于 agent run。

**建议**：在 Gateway 的 session.start handler 中，将 prepare 作为 session 初始化的强制步骤，而非可选步骤。

---

## Fix 7 [P2 — Plugin 层] `sinceUnixMs` 过滤导致 agent 早期输出被遗漏

**文件**: `src/exportArtifacts.ts`
**函数**: `collectCandidates()`
**行号**: 520-523

```typescript
const changedAtMs = Math.max(stat.mtimeMs, stat.ctimeMs);
if (changedAtMs < input.sinceUnixMs) {
  continue;
}
```

**问题**: 当 `sinceUnixMs` 参数被设置为 session.start 之后的时间戳，agent 在 session.start 之前写入的文件被过滤。在并发场景下，若 artifact scope 在另一个线程中被创建、文件被写入，然后当前 run 的 `sinceUnixMs` 晚于这些文件的时间戳 → 文件被误过滤。

**修复**: 对 scope 根目录的 `birthtime` 做校验——如果 scope 目录本身是在当前 run 中创建的，则 `sinceUnixMs` 不应过滤掉 scope 创建后写入的文件：

```typescript
// 在 collectCandidates 调用前（行 246-255）
let effectiveSince = sinceUnixMs;
if (scopePrepared && sinceUnixMs > 0) {
  try {
    const scopeStat = await fs.stat(scopeRoot);
    effectiveSince = Math.max(sinceUnixMs, scopeStat.birthtimeMs);
  } catch {}
}
```

---

## 修复优先级汇总

| Fix | 层 | 优先级 | 文件 | 函数 | 行号 |
|-----|-----|--------|------|------|------|
| 0 | Plugin | P0 | `src/exportArtifacts.ts` | `exportXWorkmateArtifacts()` | 238-259 |
| 1 | App | P0 | `external_code_agent_acp_desktop_transport.dart` | `_recoveredResultFromTaskSnapshot()` | 403-407 |
| 6 | Plugin | P1 | `src/exportArtifacts.ts` | `exportXWorkmateArtifacts()` | 242-258 |
| 2 | App | P1 | `external_code_agent_acp_desktop_transport.dart` | `_recoverTaskResultAfterStreamClosure()` | 252-279 |
| 3 | App | P1 | `app_controller_desktop_runtime_helpers.dart` | `persistGoTaskArtifactsForSessionInternal()` | 876-882 |
| 5 | App | P2 | `app_controller_desktop_thread_actions.dart` | `pollOpenClawTaskAssociationInternal()` | 786-791 |
| 4 | App | P2 | `app_controller_desktop_runtime_helpers.dart` | `_artifactBytesResultInternal()` | 917-924 |
| 7 | Plugin | P2 | `src/exportArtifacts.ts` | `collectCandidates()` | 520-523 |

## 验证状态

| 验证项 | 状态 |
|--------|------|
| OpenClaw Gateway Web (`openclaw.svc.plus`) | ⚠️ 未执行 — Chrome 未连接 + egress 未放行 |
| Bridge SSH (`xworkmate-bridge.svc.plus`) | ⚠️ 未执行 — DNS 无法解析 |
| Flutter 单元测试 | ⚠️ 未执行 — Flutter SDK 不在 VM |
| Plugin 单元测试 (`pnpm test`) | ⚠️ 未执行 — pnpm 不在 VM |
| 四层源码静态分析 | ✅ 完成 — 8 个修复点，跨 4 个文件 |
