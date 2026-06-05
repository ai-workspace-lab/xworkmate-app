# Cross-Repo Call Relation Analysis

Date: 2026-06-05
Scope: xworkmate-app, xworkmate-bridge, openclaw-multi-session-plugins, openclaw.svc.plus (ref), playbooks (deploy)

---

## 1. 仓库角色与依赖方向

```
┌──────────────────────────────┐
│  xworkmate-app (Flutter)     │  Desktop UI + 本地状态
│  版本: 1.1.4+1               │  用户线程、任务对话框、artifact 面板
└──────────────┬───────────────┘
               │ JSON-RPC over WebSocket/HTTP
               │ Path: /acp, /acp/rpc
               │ Auth: Bearer <BRIDGE_AUTH_TOKEN>
               ▼
┌──────────────────────────────┐
│  xworkmate-bridge (Go)       │  ACP 控制面 + 路由引擎
│  版本: v1.1.0                │  任务编排、concurrency gate
│  Port: 8787                  │  artifact download proxy
└──────────────┬───────────────┘
               │ Custom JSON-RPC over WebSocket v4
               │ Auth: Ed25519 device identity + shared token
               ▼
┌──────────────────────────────┐
│  openclaw.svc.plus (Node/TS)│  Agent 运行时 + 工具执行
│  Port: 18789                 │  browser、image-gen、video-gen 等工具
│  State: ~/.openclaw/         │  全局 media cache: media/browser/ 等
└──────────────┬───────────────┘
               │ Plugin SDK (Gateway RPC)
               ▼
┌──────────────────────────────┐
│  openclaw-multi-session-     │  多会话 artifact 管理
│  plugins (TS)                │  文件输出: tasks/<session>/<run>/
└──────────────────────────────┘
```

仓库 `playbooks` 是 Ansible 部署基础设施，管理 xworkmate-bridge 的 systemd、Caddy、VPN 拓扑。它不是运行时调用链的一部分，但控制 bridge 的 config.yaml 注入和环境变量。

---

## 2. 三大调用链

### 链路 A: 任务执行链（主流程）

```
1. xworkmate-app
   AssistantPage.sendChatMessage()
   → AppController.sendChatMessage()
   → ExternalCodeAgentAcpDesktopTransport.executeTask()
   → GatewayAcpClient.request('session.start' | 'session.message')
   → WebSocket POST /acp with routing params

2. xworkmate-bridge
   http_handler.Handler() → handleRequest()
   → orchestrator.Process()
   → routing engine: Resolve(params, prompt, memory)
   → openClawGatewayAdmissionGate.acquire()  // max 5 concurrent, 20 queued
   → startOpenClawGatewayTask()
     → openClawArtifactPrepare()    // calls xworkmate.artifacts.prepare
     → gatewayruntime.send('chat.send')
     → startOpenClawTaskMonitor()   // background probe every 1s

3. openclaw.svc.plus
   Gateway receives 'chat.send'
   → Agent runner processes turn
   → Tools (browser, image-gen, etc.) execute
   → Tool outputs go to ~/.openclaw/media/* or /tmp/openclaw/*  ← CRITICAL

4. openclaw-multi-session-plugins
   prepareXWorkmateArtifacts() → creates tasks/<session>/<run>/
   exportXWorkmateArtifacts()  → scans ONLY tasks/<session>/<run>/
   → returns manifest + base64 files to bridge

5. xworkmate-bridge
   openClawArtifactExport() → collects artifacts from plugin
   → completeOpenClawTask() → builds terminal snapshot
   → sends session.update (SSE) to app

6. xworkmate-app
   ExternalCodeAgentAcpDesktopTransport receives SSE
   → applies gateway chat result
   → syncArtifactsFromBridge() → writes to local ~/.xworkmate/threads/<session>/
```

### 链路 B: Artifact 回传链

```
openclaw.svc.plus (tool saves file to media/browser/)
    → Agent declares output file path
    → Multi-session plugin: detectPathIsOutsideTaskScope(path)
      → FILE IS SKIPPED — not in tasks/<session>/<run>/
    → exportXWorkmateArtifacts returns incomplete manifest
→ xworkmate-bridge: terminal snapshot has no artifacts
→ xworkmate-app: lastArtifactSyncStatus=no-exported-artifacts
```

### 链路 C: Bridge Distributed Forwarding 链

```
xworkmate-app → xworkmate-bridge (primary, 172.29.10.1:8787)
  → distributedTaskRouter selects node
  → HTTP POST → cn-xworkmate-bridge (edge, 172.29.10.2:8787)
    over WireGuard VPN tunnel
  → Forward headers:
    X-XWorkmate-Forward-Source: <nodeId>
    X-XWorkmate-Forward-Target: <nodeId>
    X-XWorkmate-Forward-Hop: <N>
```

---

## 3. 协议边界

### ACP 协议（App ↔ Bridge）

- **Transport:** WebSocket GET `/acp` 或 HTTP POST `/acp/rpc`
- **Format:** JSON-RPC 2.0
- **Auth:** `Authorization: Bearer <BRIDGE_AUTH_TOKEN>`
- **Methods:**
  | Method | 方向 | 说明 |
  |--------|------|------|
  | `acp.capabilities` | → | 获取 provider/gateway catalog |
  | `session.start` | → | 开始会话 |
  | `session.message` | → | 续写会话 |
  | `session.cancel` / `session.close` | → | 终止会话 |
  | `xworkmate.routing.resolve` | → | 路由预查询 |
  | `xworkmate.gateway.connect` | → | 建立 gateway 连接 |
  | `xworkmate.gateway.request` | → | gateway 代理请求 |
  | `xworkmate.tasks.get` | → | 查询异步任务快照 |
  | `xworkmate.tasks.cancel` | → | 取消异步任务 |
  | `xworkmate.tools.invoke` | → | 工具调用 |
  | `xworkmate.desktop.*` | ↔ | WebRTC 桌面流 |
  | `session.update` | ← | SSE 推送 (bridge→app) |

### Gateway 协议（Bridge ↔ OpenClaw）

- **Transport:** WebSocket to gateway endpoint
- **Format:** Custom JSON-RPC v4
- **Auth:** Ed25519 device identity signing + shared token
- **Methods:**
  | Method | 方向 | 说明 |
  |--------|------|------|
  | `connect` | → | 建立 gateway 会话 |
  | `chat.send` | → | 提交 agent 任务 |
  | `agent.wait` | → | 轮询任务状态 (1s timeout) |
  | `agent.cancel` | → | 取消任务 |
  | `xworkmate.artifacts.prepare` | → | 分配 artifact 目录 |
  | `xworkmate.artifacts.export` | → | 导出 artifact |
  | `xworkmate.artifacts.read` | → | 读取单个 artifact |
  | `tools.invoke` | → | 调用 OpenClaw 工具 |

### Artifact 协议（Plugin ↔ File System）

- **Scope creation:** `tasks/<safeSessionKey>/<safeRunId>/` under workspace root
- **Scope validation:** `isWithinRoot(workspaceRoot, scopeRoot)` — 防止路径穿越
- **Security:** HMAC-SHA256 签名 artifact ref，24h TTL
- **Bridge download proxy:** `/artifacts/openclaw/download?ref=<signed>&t=<expiry>`

---

## 4. 关键数据结构

### OpenClawTaskRecord（xworkmate-bridge）

```go
type OpenClawTaskRecord struct {
    SessionID, ThreadID, TurnID, RunID string  // 四元组标识
    SessionKey         string                   // 传递给 plugin 做 scope
    GatewayProviderID  string                   // "openclaw"
    TaskLoadClass      string                   // short_task/long_task/complex_chain_task
    ArtifactSinceUnixMs int64                   // artifact 时间窗口起始
    RuntimeBudgetMinutes int                    // 10/30/60
    StartedAt, DeadlineAt, LastProbeAt time.Time
    ProgressStage, ProgressMessage string
    ProgressTerminal   bool
    FirstSilentFailureAt time.Time              // 静默失败计时
    PreparedArtifact   *openClawPreparedArtifactScope
    ArtifactContract   openClawArtifactContract
    AdmissionRelease   func()                   // 释放并发槽位
}
```

### Session Key 格式

```
agent:<agentId>:<sessionId>
```

由 `agentIdFromSessionKey()` 解析（exportArtifacts.ts:730-736），用于查找 agent config 中的 workspace 路径。

### Artifact Ref

```
<sessionKey>::<runId>::<relativePath>::<hmac>
```

- HMAC-SHA256 with plugin-configured signing secret
- 24h expiry
- Bridge 验证后代理下载

### ArtifactScope（plugin）

```
tasks/<safeSessionKey>/<safeRunId>/
```

- `safeSessionKey` = sanitize(sessionKey): replace [/\\:*?"<>|] with -, truncate 96 chars
- `safeRunId` = sanitize(runId): same rules

---

## 5. 调用链入口（xworkmate-app 侧）

### 主入口：AssistantPage.sendChatMessage()

```
lib/features/assistant/assistant_page.dart
  → assistant_page_state_actions.dart: sendChatMessage()
    → app_controller_openclaw_task_queue.dart: queueOpenClawGatewayWork()
    → go_task_service_desktop_service.dart: DesktopGoTaskService.startSession()
    → external_code_agent_acp_desktop_transport.dart: executeTask()
      → GatewayAcpClient.request('session.start')   via WebSocket  /acp
      → GatewayAcpClient.request('session.message')  via WebSocket  /acp
      → pollBridgeTaskSnapshot() → 'xworkmate.tasks.get'
```

### 恢复入口：AppController.resumeOpenClawRunningTask()

```
app_controller_desktop_thread_sessions.dart: resolveGatewayThreadConnectionState()
  → 检查 localLastRunId 是否对应一个未完成的 OpenClaw 任务
  → external_code_agent_acp_desktop_transport.dart: pollBridgeTaskSnapshot()
  → 'xworkmate.tasks.get' → 获取 terminal snapshot
```

### 取消入口：AppController.cancelCurrentTask()

```
assistant_page_state_actions.dart: onCancelTask()
  → external_code_agent_acp_desktop_transport.dart: cancelAndCloseTask()
    → 'session.cancel' 或 'xworkmate.tasks.cancel'
```

---

## 6. 最容易改坏的 10 个地方

### 🔴 CRITICAL: 路径断裂区

**6.1 OpenClaw 工具输出路径 ≠ plugin artifact scope**

OpenClaw 工具（browser screenshot、image generation、video render、file write）将输出写到:
- `~/.openclaw/media/browser/<uuid>.png` — `saveMediaBuffer(buffer, contentType, "browser")`
- `~/.openclaw/media/inbound/<uuid>.<ext>` — 上传/附件
- `/tmp/openclaw/downloads/` — 浏览器下载
- `/tmp/openclaw/traces/` — 工具 trace

但 `exportXWorkmateArtifacts()` 只扫描 `tasks/<session>/<run>/`。

**后果:** 工具生成的图片、文档、视频在 artifact 回传时被静默丢弃。用户收到 "no-exported-artifacts"。

**触发条件:** 任何使用 OpenClaw 内置工具（browser、image-gen、video-gen）的任务，如果工具输出没有显式复制到 `tasks/<session>/<run>/` 下。

**修复方向:**
- 方案 A: 在 plugin 的 `exportXWorkmateArtifacts` 增加对 `~/.openclaw/media/browser/` 的扫描（按 session 过滤）
- 方案 B: 修改 OpenClaw 工具，使其在 gateway session 上下文中使用 session-scoped 输出路径
- 方案 C: 在 bridge 的 `openClawArtifactExport()` 中，额外从 gateway 查询 media cache 中的当前 session 产物

**6.2 Session Key 派生不一致**

Session key 由多个来源派生:
- App: `ExternalCodeAgentAcpDesktopTransport._sessionKey` — 从 response params 获取
- Bridge: `OpenClawTaskRecord.SessionKey` — 从 gateway response 获取
- Plugin: `agentIdFromSessionKey(sessionKey)` — 解析 `agent:<id>:<session>` 格式

如果任一端对 session key 的生成或传递逻辑发生变化，artifact scope 将不匹配。

**验证方法:** 在 artifact prepare/export 两端打印 sessionKey，确保完全一致。

**6.3 Bridge 的 artifact prepare 时序**

`openClawArtifactPrepare()` 在 bridge 侧通过 gateway 调用 `xworkmate.artifacts.prepare`，但该调用发生在 `chat.send` 之前还是之后决定了 scope 目录是否存在。

当前代码: `startOpenClawGatewayTask()` 先 prepare 再 send — 正确。但如果在 send 之前 prepare 失败（超时、gateway 不可达），任务仍会提交但无 scope 目录。

**6.4 Artifact ref 签名密钥轮换**

HMAC-SHA256 签名密钥在 plugin config 中的 `artifactRefSigningSecret`。如果密钥变更，旧的 artifact ref 全部失效。Bridge 的 download proxy 会返回 403。

**6.5 Bridge admission gate 满时静默丢失**

`openClawGatewayAdmissionGate.acquire()`:
- maxActive: 5
- maxQueued: 20
- queueTimeout: 10 min

当队列满且超时，返回 `OPENCLAW_GATEWAY_BUSY`。App 端是否有正确处理？检查 `app_controller_openclaw_task_queue.dart` 中的 `drainOpenClawGatewayQueue` 逻辑。

**6.6 Bridge 会话纯内存存储**

xworkmate-bridge 的 session 存储在 `Server.sessions map[string]*session`，不持久化。Bridge 重启 → 所有运行中的任务丢失 → App 端 `xworkmate.tasks.get` 返回 "session not found" → 任务静默失败。

### 🟠 HIGH: 状态同步区

**6.7 TaskSnapshot 字段不完整**

Bridge 返回的 terminal snapshot 依赖 `completeOpenClawTask()` 正确组装 artifact 列表。如果 plugin 返回的 artifact manifest 中有文件但内容为空、或相对路径超出 scope，bridge 的 snapshot 会缺少 artifact 条目。

**6.8 SSE 流中断后的轮询策略**

当 SSE stream 关闭（网络断开、bridge 重启），app 的 `ExternalCodeAgentAcpDesktopTransport` 进入 polling 模式调用 `xworkmate.tasks.get`。如果轮询间隔、重试次数、超时策略设置不当，可能导致:
- 轮询过早结束（任务实际还在跑）
- 轮询永不结束（bridge 已重启 session 丢失）

**6.9 Plugin 的 workspace 解析回退链过长**

`resolveWorkspaceDir()` 的回退链:
1. 显式 params.workspaceDir
2. pluginConfig.workspaceDir
3. agent config (按 agentId 匹配 → default agent → 第一个 agent)
4. OPENCLAW_PROFILE env → `~/.openclaw/workspace-<profile>`
5. `~/.openclaw/workspace`

如果 agent config 变更（增删 agent、修改 default、调整 workspace），可能影响所有运行中 session 的 artifact 路径。

### 🟡 MEDIUM: 配置与部署区

**6.10 Distributed bridge forwarding topology 变更**

Bridge 的双节点拓扑（primary + edge）定义在 `config.yaml` 的 `distributed.nodes`。拓扑变更（增删节点、修改 endpoint、更新转发规则）会影响跨区域任务路由。session stickiness（24h TTL）意味着变更后已有 session 可能被路由到错误的节点。

---

## 7. tasks/<session>/<run> 状态矩阵

| 阶段 | 状态 | 文件位置 | 谁负责 |
|------|------|----------|--------|
| prepare | `xworkmate.artifacts.prepare` 调用 | plugin 创建空目录 | multi-session-plugins |
| execute | Agent 工具运行 | 工具输出到 `~/.openclaw/media/` 或 `/tmp/` | openclaw.svc.plus |
| — | **GAP: 工具输出不在 scope 内** | files in media/, NOT in tasks/ | 无人负责 |
| export | `xworkmate.artifacts.export` 扫描 | 扫描 `tasks/<session>/<run>/` | multi-session-plugins |
| snapshot | bridge 组装 terminal snapshot | 内存中, 通过 `xworkmate.tasks.get` 查询 | xworkmate-bridge |
| sync | app 下载 artifact 到本地 | `~/.xworkmate/threads/<session>/` | xworkmate-app |

**核心 gap:** execute 阶段工具写文件到全局路径 → export 阶段只扫描 task scope → 文件不可见。

---

## 8. 建议沉淀的 chain-map.md

| 链路 | 文件名 | 覆盖范围 |
|------|--------|----------|
| A | `chain-map-task-execution.md` | App→Bridge→OpenClaw→Plugin 完整任务执行 |
| B | `chain-map-artifact-lifecycle.md` | Artifact prepare/export/read/download 全周期 |
| C | `chain-map-bridge-distributed.md` | Bridge 分布式转发拓扑 |
| D | `chain-map-session-recovery.md` | App 会话恢复、task.get 轮询、bridge 重启恢复 |
