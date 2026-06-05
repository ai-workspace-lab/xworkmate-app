# openclaw-multi-session-plugins 代码审核报告

> 基于架构优化建议，审核已实施改动的完善程度

## 审核范围

| 仓库 | 分支/状态 | 审核提交范围 |
|------|----------|-------------|
| openclaw-multi-session-plugins | release/v2026.6.1 (uncommitted changes) | `c462ed6..HEAD` + staged diffs |
| xworkmate-app | main (ahead 8) | `6219fcd..596704b` |
| openclaw.svc.plus | main (uncommitted `src/plugins/session-scope.ts`) | 仅新增文件 |
| xworkmate-bridge | 无此仓库 | — |

---

## 一、P0 改动审核

### 1.1 注册 xworkmate.tasks.get ✅ 已实施，有细节问题

**实施状态**：`index.ts` 新增了 `api.registerGatewayMethod("xworkmate.tasks.get", ...)`，委托给 `taskState.ts` 的 `getXWorkmateTaskSnapshot()`。

**测试覆盖**：`index.test.ts` 新增了完整集成测试（`registers xworkmate task state against the native session extension and task runtime seams`），验证了 session.start hook → 制品写入 → tasks.get 查询 → 状态/制品同时返回。

**问题**：

1. **`getXWorkmateTaskSnapshot` 中的 `api.runtime.tasks.runs.bindSession` 调用路径不确定**。`taskState.ts:229-236` 的 `resolveNativeTask` 走 `api.runtime?.tasks?.runs?.bindSession?.({ sessionKey })` 查询原生 TaskRecord。但 `api.runtime` 在 OpenClaw 2026.6.1 的 Plugin API 契约中的暴露方式需要通过 Gateway Handler 的 context 注入，而非直接从 `api` 对象获取。测试中显式 mock 了这个路径（第 139-153 行），生产路径需要验证。

2. **`registerXWorkmateDetachedTaskRuntime` 使用了未文档化的 API**。`taskState.ts:64` 调用 `(api as any).registerDetachedTaskRuntime` —— 这个 API 不在 `OpenClawPluginApi` 类型中，也不在 `src/plugin-sdk/index.ts` 的导出里。如果OpenClaw 原生不支持，调用会静默失败（`typeof registerRuntime !== "function"` 的 guard），退回到纯内存 store 模式。这不影响功能但失去了与原生 task-registry 的集成。

**评级**：基本完善。`registerDetachedTaskRuntime` 的可用性是关键风险点，需要验证 OpenClaw 2026.6.1 是否实际支持。

### 1.2 session.start hook 中创建 TaskRecord ✅ 已实施

**实施状态**：`index.ts:99-115` 在 `session.start` hook 中调用 `createOrUpdateXWorkmateTaskRecord(taskStore, { params, status: "running" })`，并行调用 `prepareXWorkmateArtifacts`。

**问题**：

1. **TaskStore 是纯内存 Map**。`taskState.ts:33-35` 创建 `{ records: new Map() }` 作为 task store，不支持持久化。插件重启后所有 task 记录丢失。如果 OpenClaw 原生 task-registry 集成生效，这不影响（原生 registry 持久化）；如果退回到内存模式，丢失意味着 APP 的 `xworkmate.tasks.get` 查询返回不到历史任务状态。

2. **没有 task 生命周期终点同步**。Hook 只在 `session.start` 时创建 `status: "running"` 的 record，但没有在任务完成时更新为 `"succeeded"` / `"failed"`。`getXWorkmateTaskSnapshot` 虽然会根据制品数量推断（`taskState.ts:132-136`），但这依赖于每次调用时做推断而非推送。

**评级**：功能可用，但内存 store + 没有主动完成通知是两个改进点。

### 1.3 打通 expectedArtifactDirs 全链路 ⚠️ 部分实施

**实施状态**：

| 层 | 状态 | 说明 |
|----|------|------|
| Plugin - scopedGatewayParams | ✅ 已通 | 使用 `{ ...params, sessionKey, runId, ... }` 模式，额外参数自然透传 |
| Plugin - exportXWorkmateArtifacts | ✅ 已实现 | Fix 0 的回退扫描逻辑在 `exportArtifacts.ts:263-283` |
| Plugin - 测试覆盖 | ✅ 已验证 | `index.test.ts:104-137` 端到端验证 |
| Bridge | ❌ 未实施 | Bridge 仓库不存在于此工作区 |
| APP - 发送 expectedArtifactDirs | ❌ 未实施 | `xworkmateTaskArtifactContract` 不包含此字段 |

**关键缺失**：APP 侧的 `gatewayTaskMetadataWithArtifactContractInternal`（`app_controller_desktop_thread_actions.dart:988-1000`）需要在 metadata 中加入 `expectedArtifactDirs`：

```dart
'xworkmateTaskArtifactContract': <String, dynamic>{
  'version': 1,
  'sessionKey': sessionKey,
  'expectedArtifactDirs': ['assets/images', 'reports', 'video'],  // ← 缺失
  // ...
},
```

没有这行，即使 Plugin 侧的回退逻辑已就绪，参数也不会到达。

---

## 二、P1 改动审核

### 2.1 利用 pluginExtensions 做 Key 映射 ✅ 已实施，路径需验证

**实施状态**：`taskState.ts:37-61` 的 `registerXWorkmateSessionExtension` 调用 `api.session?.state?.registerSessionExtension` 注册 `"xworkmate"` namespace 的 session extension。

`project` 回调实现了自动映射：
- 如果 state 有 `appSessionKey` → 直接用
- 否则从 OpenClaw session key 推导（`agent:main:draft:xxx` → `draft:xxx`）

**风险**：`api.session?.state?.registerSessionExtension` 的类型链依赖 `OpenClawPluginApi` 的类型定义。`taskState.ts:38` 有 `?? (api as any).registerSessionExtension` 后备，但同样，如果 OpenClaw 不支持这个 API，静默失败。

**评级**：设计方向正确。`api.session.state.registerSessionExtension` 是 OpenClaw 的 `api-facades.ts` 中定义的正式 API（`api.session.state`），应该可用。Key 映射逻辑也正确处理了 `agent:main:draft:1780636411666238-3` → `draft:1780636411666238-3` 的 case。

### 2.2 Fix 1 (引用相等 Bug) ✅ 已修正

`external_code_agent_acp_desktop_transport.dart:178-184` 的 `_recoveredResultFromTaskSnapshot` 已经修正：去掉了 `result['artifacts'] == artifactRecord` 的引用相等比较，改为直接判断 `artifactItems is List && artifactItems.isNotEmpty`。

### 2.3 Fix 2 (completed 状态竞态) ✅ 已修正

`_recoverTaskResultAfterStreamClosure:186-192` 新增了产物为空时的重试逻辑。

### 2.4 Fix 3 (产物完整性验证) ✅ 已修正

`app_controller_desktop_runtime_helpers.dart:873-888` 的 `persistGoTaskArtifactsForSessionInternal` 现在检查 `requiredArtifactExtensions`，缺失时设置 syncStatus 为 `'partial'`。

---

## 三、P2 改动审核

### 3.1 Fix 5 (polling 产物完整性) ✅ 已修正

`app_controller_desktop_thread_actions.dart:778-785` 的 `pollOpenClawTaskAssociationInternal` 现在在 polling 完成时检查 `requiredArtifactExtensions`，不足时最多重试 3 次。

### 3.2 bridgeAgents 改用原生 subagent.run ❌ 未实施

`bridgeAgents.ts` 仍通过 HTTP fetch 调用外部 bridge，没有使用 OpenClaw 的 `api.runtime.subagent.run()` 或 `api.taskFlows`。这个改动属于较大重构，优先级较低，暂未实施可以接受。

### 3.3 用 Transcript Events 替代 SSE 管理 ❌ 未实施

无相关改动。这个改动涉及 Bridge 层架构变更，当前未实施。

---

## 四、OpenClaw 原生侧待确认项

### 4.1 session-scope.ts（未提交）

`openclaw.svc.plus/src/plugins/session-scope.ts` 是一个未提交的新增文件，提供了标准化的 plugin session scope 管理（`createPluginSessionScope`、`normalizePluginScopeSegment`、`buildPluginRelativeTaskDirectory`）。这个文件的意图看起来是为了将 session-scope 管理提升为 OpenClaw 原生能力，但目前只是未提交的草案。

**建议**：如果 OpenClaw 上游接受了这个模块，`openclaw-multi-session-plugins` 的 `scopedGatewayParams` 和 `safeScopeSegment` 可以迁移使用原生 API。

### 4.2 registerDetachedTaskRuntime 的可用性

`taskState.ts:63-114` 通过 `(api as any).registerDetachedTaskRuntime` 注册自定义 detached task runtime。需要在 OpenClaw 2026.6.1 中验证此 API 是否存在。如果不存在，退回到纯内存 store 模式不影响核心功能。

---

## 五、整体评估

### 5.1 实施完成度

| 类别 | 总项 | 已完成 | 部分完成 | 未开始 |
|------|------|--------|---------|--------|
| P0 | 3 | 2 | 1 (expectedArtifactDirs APP侧) | 0 |
| P1 | 4 | 4 | 0 | 0 |
| P2 | 3 | 1 | 0 | 2 |
| **合计** | **10** | **7** | **1** | **2** |

### 5.2 待补充的关键项

1. **APP 侧传递 expectedArtifactDirs** — `gatewayTaskMetadataWithArtifactContractInternal` 需要在 metadata 中加入 `'expectedArtifactDirs': ['assets/images', 'reports', 'video']`

2. **Bridge 侧透传 expectedArtifactDirs** — `session.start` 参数需要在 `toExternalAcpParams()` 中包含 `expectedArtifactDirs` 字段

3. **验证 registerDetachedTaskRuntime API** — 确认 OpenClaw 2026.6.1 是否实际支持此 API；如果不支持，考虑不依赖它，纯用内存 store + export

### 5.3 架构风险

| 风险 | 严重度 | 说明 |
|------|--------|------|
| TaskStore 纯内存 | 中 | 插件重启后 task 记录丢失，但 APP polling 会重新触发查询 |
| registerDetachedTaskRuntime 静默失败 | 低 | 有 fallback 路径，功能不中断 |
| 未提交代码量大 | 中 | 插件 6 个文件有 staged changes，taskState.ts 是新文件 |
| 缺少 task 完成推送 | 中 | session.start hook 只创建 running 状态，无完成时的更新 |
| OpenClaw session-scope.ts 的定位 | 信息 | 如果上游接受，部分插件逻辑可以删除 |

---

## 六、结论

**核心 P0 改动（xworkmate.tasks.get + 原生 TaskRecord 集成）实施质量良好**，代码结构清晰，测试覆盖到位。主要缺陷在 `expectedArtifactDirs` 的全链路——Plugin 侧已就绪，但 APP 和 Bridge 两侧各缺一行代码。补充这两处后，所有三个 P0 项即全部完成。

P1 改动（ROOT_CAUSE_ANALYSIS 的 Fix 1-3）全部正确实施，产物完整性问题已解决。
