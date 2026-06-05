# openclaw-multi-session-plugins 架构优化建议

> 基于 OpenClaw 2026.6.1 原生能力，简化多会话插件设计

## 一、核心原则

**尽可能复用 OpenClaw 2026.6.1 原生的能力。** 插件只做 OpenClaw 原生不提供的事：逻辑隔离的多会话制品作用域管理。任务生命周期、会话管理、状态同步全部委托给 OpenClaw 原生机制。

## 二、当前问题全景

### 2.1 任务完成无法感知（核心痛点）

OpenClaw 任务执行完了，APP 侧还在"运行中"，制品也没同步。根因在于：

```
APP 侧 polling → xworkmate.tasks.get → Bridge → ??? → OpenClaw
                                                    ↑
                                              这里断了
```

**具体原因**：

1. **openclaw-multi-session-plugins 必须注册 `xworkmate.tasks.get` gateway method**。插件的目标接口只保留 `xworkmate.tasks.get` 和 `xworkmate.artifacts.*`，不再暴露 bridge-backed `xworkmate.agents.run`。

2. **插件没有在 OpenClaw 原生 task-registry 中创建 TaskRecord**。OpenClaw 的 `task-registry.ts` 是任务状态的唯一权威来源（`TaskRecord { taskId, runId, status, requesterSessionKey, ... }`），但插件完全绕过了它，自己管理制品作用域，没有任何原生任务记录。

3. **SSE 流断开后的恢复路径脆弱**。APP 的 `_recoverTaskResultAfterStreamClosure` 和 `pollOpenClawTaskAssociationInternal` 都依赖 `xworkmate.tasks.get`，但这个方法在 OpenClaw 侧没有实现，只能靠 Bridge 自己维护状态。

### 2.2 expectedArtifactDirs 参数断裂

```
APP (metadata.xworkmateTaskArtifactContract) → session.start params
  → Bridge (转发) → Plugin scopedGatewayParams()
                                           ↑
                                   这里丢失了 expectedArtifactDirs
```

- `scopedGatewayParams()` 只映射 `sessionKey`, `runId`, `workspaceDir`, `artifactScope`
- `expectedArtifactDirs` 不在映射中
- 旧 `bridgeAgents.ts` 反向 HTTP 路径已移除，不能再作为参数补偿路径
- 虽然 Fix 0 在 `exportXWorkmateArtifacts` 中加了回退扫描逻辑（行 263-283），但这个逻辑永远不会被触发，因为参数从未到达

### 2.3 会话 Key 映射没有双向约定

- APP 使用: `draft:1780636411666238-3`
- OpenClaw 使用: `agent:main:draft:1780636411666238-3`
- 插件用 `safeScopeSegment()` 做单向规范化，但反向查询时无法从 OpenClaw session key 推导出 APP session key
- 没有利用 OpenClaw 的 `SessionEntry.pluginExtensions` 存储双向映射

### 2.4 插件边界过于厚重

当前插件的职责混合了：
- 制品作用域管理（合理的独特价值）
- 旧版通过 bridgeAgents 做 HTTP RPC 调用（已移除，避免 Plugin→Bridge 循环依赖）
- 隐式的任务状态追踪（没有利用原生 task-registry）
- 会话上下文传递（绕过了原生 session store）

## 三、OpenClaw 2026.6.1 可复用的原生能力

| 原生能力 | 位置 | 可以替代的当前实现 |
|---------|------|-----------------|
| Task 注册与状态机 | `src/tasks/task-registry.ts` | APP 侧的 polling 循环、恢复逻辑 |
| Task Flow 编排 | `src/tasks/task-flow-registry.ts` | Bridge/OpenClaw 原生多代理编排 |
| Session 持久化 | `src/config/sessions/store.ts` | 会话 key 映射、上下文存储 |
| Plugin Extensions | `SessionEntry.pluginExtensions` | 零散的上下文传递 |
| Session Key 解析 | `src/sessions/session-key-utils.ts` | `safeScopeSegment()` 字符串处理 |
| Gateway 路由解析 | `src/routing/resolve-route.ts` | APP 侧的 routing 配置 |
| Plugin API Facades | `src/plugins/api-facades.ts` | 直接操作底层 API |
| Transcript 事件 | `src/sessions/transcript-events.ts` | SSE 流的手动管理 |
| Compaction Checkpoint | `src/gateway/session-compaction-checkpoints.ts` | 制品快照 |

## 四、优化方案

### 4.1 核心改动：注册 xworkmate.tasks.get，对接原生 Task Registry

在 `index.ts` 的 `register()` 中新增 gateway method：

```typescript
api.registerGatewayMethod("xworkmate.tasks.get", async (opts: GatewayRequestHandlerOptions) => {
  try {
    const params = scopedGatewayParams(opts.params);
    const runId = optionalString(params.runId);
    const sessionKey = optionalString(params.sessionKey);

    // 1. 从 OpenClaw 原生 task registry 查询任务状态
    const taskRegistry = api.taskRegistry; // 通过 PluginRuntime 暴露
    let taskRecord = null;
    if (runId) {
      taskRecord = await taskRegistry.findByRunId(runId);
    }

    // 2. 查询制品导出状态
    let artifactPayload = null;
    if (sessionKey && runId) {
      try {
        artifactPayload = await exportXWorkmateArtifacts({
          params: { sessionKey, runId, workspaceDir: params.workspaceDir },
          config: api.config,
          pluginConfig: api.pluginConfig,
        });
      } catch { /* artifacts optional */ }
    }

    // 3. 合并返回
    const result: Record<string, unknown> = {
      sessionId: sessionKey,
      runId: runId,
      status: taskRecord?.status ?? (artifactPayload ? "completed" : "unknown"),
      ...(taskRecord ? {
        taskId: taskRecord.taskId,
        startedAtMs: taskRecord.createdAt,
        runtimeBudgetMinutes: taskRecord.runtimeBudgetMinutes,
      } : {}),
      ...(artifactPayload ? {
        remoteWorkingDirectory: artifactPayload.remoteWorkingDirectory,
        remoteWorkspaceRefKind: artifactPayload.remoteWorkspaceRefKind,
        artifactScope: artifactPayload.artifactScope,
        artifacts: artifactPayload.artifacts,
        warnings: artifactPayload.warnings,
      } : {}),
    };
    opts.respond(true, result, undefined);
  } catch (error) {
    opts.respond(false, undefined, {
      code: "TASK_GET_FAILED",
      message: error instanceof Error ? error.message : String(error),
    });
  }
});
```

同时在 `session.start` hook 中创建原生 TaskRecord：

```typescript
api.registerHook("session.start", async (event: any) => {
  try {
    const params = scopedGatewayParams(event?.context ?? event);
    if (params.sessionKey && params.runId) {
      // 创建原生 TaskRecord（复用 OpenClaw task-registry）
      await api.taskRegistry.createTask({
        taskId: `xworkmate-${params.runId}`,
        runtime: "subagent", // 或新增 "xworkmate" runtime type
        requesterSessionKey: params.sessionKey,
        ownerKey: params.sessionKey,
        status: "running",
        runId: params.runId,
      });
      // 准备制品作用域
      await prepareXWorkmateArtifacts({ params, config: api.config, pluginConfig: api.pluginConfig });
    }
  } catch (e) {
    // best-effort
  }
});
```

**收益**：
- 任务状态有原生 TaskRecord 作为权威来源，状态机由 OpenClaw 管理（queued → running → succeeded/failed）
- APP 的 `pollOpenClawTaskAssociationInternal` 和 `_recoverTaskResultAfterStreamClosure` 直接查询到真实状态
- 不再依赖脆弱的 SSE 流恢复逻辑

### 4.2 打通 expectedArtifactDirs 全链路

**Step 1 — Plugin 侧**：在 `scopedGatewayParams()` 中加入透传：

```typescript
function scopedGatewayParams(params: Record<string, unknown>): Record<string, unknown> {
  const sessionScope = (getPluginRuntimeGatewayRequestScope() as XWorkmateGatewayRequestScope | undefined)?.sessionScope;
  const runScope = resolveRunScope({ sessionScope });
  if (!runScope) {
    return params;
  }
  return {
    ...params,  // ← 保留所有原始参数
    sessionKey: runScope.sessionKey,
    runId: runScope.runId,
    ...(runScope.workspaceDir ? { workspaceDir: runScope.workspaceDir } : {}),
    ...(runScope.artifactScope ? { artifactScope: runScope.artifactScope } : {}),
    // 透传 expectedArtifactDirs（不覆盖已映射的关键字段）
  };
}
```

关键改动：从 `{ ...params, sessionKey, runId, ... }` 改为先展开 params，再覆盖关键字段。这样 `expectedArtifactDirs` 等附加参数自然透传。

**Step 2 — Bridge 侧**：在 `session.start` 参数中包含 `expectedArtifactDirs`：

```typescript
// 从 xworkmateTaskArtifactContract metadata 中提取
const artifactContract = request.metadata?.['xworkmateTaskArtifactContract'];
const params = {
  sessionId: sessionKey,
  threadId: threadKey,
  taskPrompt: prompt,
  expectedArtifactDirs: artifactContract?.expectedArtifactDirs ?? ["artifacts/", "reports/", "exports/", "assets/", "assets/images/", "dist/"],
  // ...其他参数
};
```

**Step 3 — APP 侧**：在 `gatewayTaskMetadataWithArtifactContractInternal` 中加入：

```dart
'xworkmateTaskArtifactContract': {
  'version': 1,
  'sessionKey': sessionKey,
  'expectedArtifactDirs': ['artifacts/', 'reports/', 'exports/', 'assets/', 'assets/images/', 'dist/'],
  // ...existing fields
},
```

**收益**：Fix 0 的回退扫描逻辑真正生效，agent 写入 workspace 根的文件能被纳入 artifact scope。

### 4.3 利用 SessionEntry.pluginExtensions 做双向 Key 映射

```typescript
api.registerHook("session.start", async (event: any) => {
  const params = scopedGatewayParams(event?.context ?? event);
  if (params.sessionKey && params.runId) {
    // 存储双向映射
    await api.session.state.setPluginExtension(
      params.sessionKey,
      "openclaw-multi-session-plugins",
      "xworkmate",
      {
        appSessionKey: params.appSessionKey,    // ← APP 侧的 key
        appThreadId: params.threadId,
        expectedArtifactDirs: params.expectedArtifactDirs,
        artifactScope: artifactScopeFor(params.sessionKey, params.runId),
      }
    );
  }
});
```

**收益**：
- 无需在 session key 之间做脆弱的字符串推导
- 任意方向查询 O(1)
- 利用 OpenClaw 原生的 session store 持久化

### 4.4 删除 bridgeAgents 反向 HTTP 客户端

`bridgeAgents.ts`、`xworkmate.agents.run` 和 `openclaw_multi_session_agents`
不再属于插件边界。多 agent 编排归 Bridge 或 OpenClaw 原生 task/subagent
runtime，插件只负责 artifact scope、task snapshot adapter 和 session key
mapping。

**收益**：
- 消除 Plugin→Bridge→Plugin 循环依赖
- 发布包不再需要 bridgeUrl/bridgeToken 配置
- 状态同步继续由 task-registry 管理

### 4.5 用 Transcript Events 替代 SSE 流管理

OpenClaw 原生有 `transcript-events.ts`：

```typescript
// 监听 transcript 更新事件，自动通知 APP 侧
api.session.onTranscriptUpdate(params.sessionKey, (update) => {
  // 通过 Gateway push 通知 APP
  api.gateway.push("session.update", {
    sessionId: params.sessionKey,
    turnId: update.turnId,
    delta: update.delta,
    event: update.isComplete ? "completed" : "delta",
  });
});
```

**收益**：不依赖 Bridge 层的 SSE 连接稳定性，由 OpenClaw 原生事件系统驱动。

## 五、实施优先级

| 优先级 | 改动 | 涉及层 | 复杂度 | 收益 |
|--------|------|--------|--------|------|
| **P0** | 注册 xworkmate.tasks.get + 创建原生 TaskRecord | Plugin | 中 | 解决"任务完成无法感知"核心问题 |
| **P0** | 打通 expectedArtifactDirs 全链路 | Plugin + Bridge + APP | 低 | 解决制品遗漏问题 |
| **P1** | 利用 pluginExtensions 做 Key 映射 | Plugin | 低 | 消除会话 key 歧义 |
| **P1** | session.start hook 中创建 TaskRecord | Plugin | 低 | 任务状态有权威来源 |
| **P2** | 删除 bridgeAgents 反向 HTTP 客户端 | Plugin | 已完成 | 消除 HTTP 客户端依赖 |
| **P2** | 用 Transcript Events 替代 SSE 管理 | Plugin + Bridge | 高 | 简化流管理 |

## 六、简化后的架构全景

```
XWorkmate App (Flutter/Dart)
  │
  │  session.start (含 expectedArtifactDirs+metadata)
  ▼
xworkmate-bridge (Go) ── ACP JSON-RPC ── OpenClaw Gateway
  │                                         │
  │    xworkmate.tasks.get ◄────────────────┤
  │    (查询原生 TaskRegistry + artifacts)   │
  │                                         │
  │                               ┌─────────┴──────────┐
  │                               │  openclaw-multi-    │
  │                               │  session-plugins    │
  │                               │                     │
  │                               │  职责聚焦:           │
  │                               │  1. artifact scope   │
  │                               │  2. 原生 TaskRecord  │
  │                               │  3. pluginExtensions │
  │                               │                     │
  │                               │  委托给原生:         │
  │                               │  - task-registry.ts  │
  │                               │  - session store     │
  │                               │  - transcript events │
  │                               │  - subagent.run()    │
  │                               └─────────────────────┘
  │                                         │
  │                               OpenClaw 原生基础设施
  │                               (task-registry, session
  │                                store, routing, ...)
  ▼
APP 侧 polling 简化:
  pollOpenClawTaskAssociationInternal
    → xworkmate.tasks.get
      → 原生 TaskRegistry.findByRunId(runId)  ← 权威状态
      + exportXWorkmateArtifacts()             ← 权威制品
```

## 七、参考 Case

用户提供的真实案例：

- OpenClaw URL: `https://openclaw.svc.plus/chat?session=agent%3Amain%3Adraft%3A1780636411666238-3`
- APP 线程目录: `$HOME/.xworkmate/threads/draft-1780636411666238-3`

这说明 session key 的自然映射是：
- OpenClaw session key: `agent:main:draft:1780636411666238-3`
- APP session key: `draft:1780636411666238-3`

在优化后的架构中，这个映射存储在 `SessionEntry.pluginExtensions` 中，双向查询均为 O(1)。任务状态通过原生 `TaskRecord` 追踪，`xworkmate.tasks.get` 一次调用同时返回任务状态和制品列表。
