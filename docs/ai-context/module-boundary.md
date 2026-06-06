# Module Boundary — 模块边界与接口契约

> 生成日期: 2026-06-05 | 跨仓库接口定义、协议规范、安全边界

---

## 1. App ↔ Bridge: ACP 协议边界

### 端点定义

```
# WebSocket (主通道)
ws://<bridge-host>:8787/acp

# HTTP RPC (后备通道)
POST https://<bridge-host>/acp/rpc
Content-Type: application/json
Authorization: Bearer <BRIDGE_AUTH_TOKEN>
```

### JSON-RPC 2.0 请求格式

```json
{
  "jsonrpc": "2.0",
  "id": "<request-id>",
  "method": "<method-name>",
  "params": { ... }
}
```

### 方法清单

| 方法 | 方向 | 描述 | 调用方文件 |
|------|------|------|-----------|
| `health` | App→Bridge | 健康检查 | `gateway_runtime_core.dart` |
| `acp.capabilities` | App→Bridge | 查询提供商能力 | `gateway_acp_client.dart` |
| `session.start` | App→Bridge | 启动 AI 会话 | `external_code_agent_acp_desktop_transport.dart` |
| `session.message` | App→Bridge | 发送会话消息 | 同上 |
| `session.cancel` | App→Bridge | 取消会话 | 同上 |
| `session.close` | App→Bridge | 关闭会话 | 同上 |
| `xworkmate.gateway.connect` | App→Bridge | 连接远程网关 | `gateway_runtime_session_client.dart` |
| `xworkmate.gateway.request` | App→Bridge | 网关请求 | 同上 |
| `xworkmate.gateway.disconnect` | App→Bridge | 断开网关 | 同上 |
| `xworkmate.routing.resolve` | App→Bridge | 解析路由 | `gateway_acp_client.dart` |
| `xworkmate.tasks.get` | App→Bridge | 查询任务状态 | `external_code_agent_acp_desktop_transport.dart` |
| `xworkmate.tasks.cancel` | App→Bridge | 取消任务 | 同上 |
| `xworkmate.desktop.offer` | App→Bridge | WebRTC SDP offer | bridge `rpc_handler.go` |
| `xworkmate.jobs.*` | App→Bridge | 后台作业管理 | bridge `rpc_handler.go` |
| `system.logs` | App→Bridge | 获取系统日志 | bridge `rpc_handler.go` |

### SSE 推送事件

| 事件 | 方向 | 描述 |
|------|------|------|
| `xworkmate.gateway.snapshot` | Bridge→App | 网关状态快照 |
| `xworkmate.gateway.log` | Bridge→App | 网关日志 |
| `xworkmate.gateway.push` | Bridge→App | 网关推送 (chat.run 等) |

### 认证

- Bridge 验证 `Authorization: Bearer <token>` 头
- Bridge 验证 `Origin` 头 (白名单: `https://xworkmate.svc.plus`, `http://localhost:*`, `http://127.0.0.1:*`)
- SSL 证书错误自动重试 (最多 5 次)

### 超时与重试

- 请求超时: 120s
- TLS 握手失败: 最多 5 次重试
- 连接超时: 最多 2 次重试
- WebSocket: 30s ping 间隔, 10s 连接超时

---

## 2. Bridge ↔ AI Providers: 提供商适配器边界

### 通用协议

所有提供商通过 ACP JSON-RPC 2.0 通信。Bridge 作为客户端，Provider 作为服务端。

```
Bridge ── HTTP POST / WebSocket ──► Provider (codex/opencode/gemini/hermes)
Headers: Authorization: Bearer <BRIDGE_AUTH_TOKEN>
```

### Codex 适配器

```
传输: WebSocket (主) / HTTP (后备)
配置: CODEX_RPC_URL
认证: Bearer token
```

### OpenCode 适配器

```
传输: HTTP
端点: http://127.0.0.1:38993
启动: bridge 启动 opencode serve 子进程
配置: OPENCODE_RPC_URL
```

### Gemini 适配器

```
传输: HTTP
端点: http://127.0.0.1:8791
启动: bridge 通过 stdio 启动 gemini CLI 子进程
      → adapter 将 stdio JSON-RPC 转换为 HTTP
配置: GEMINI_RPC_URL
```

### Hermes 适配器

```
传输: HTTP
端点: http://127.0.0.1:3920
启动: bridge 通过 stdio 启动 hermes CLI 子进程
      → adapter 将 stdio JSON-RPC 转换为 HTTP
配置: HERMES_RPC_URL
```

### 提供商选择逻辑

Bridge 的 Router 模块根据以下因素选择提供商:
1. 请求中的 `routing.provider` 参数
2. 提供商可用性 (health check)
3. 会话亲和性 (session 绑定到特定 provider)

---

## 3. Bridge ↔ OpenClaw Gateway: 网关 RPC 边界

### 连接

```
Bridge ── WebSocket ──► OpenClaw Gateway
         ws://127.0.0.1:18789 (本地)
         wss://openclaw.svc.plus:443 (云端)

Headless 模式: 无 SSL, 直接 WS 连接
```

### 认证 (Ed25519 加密握手)

1. Bridge 生成 Ed25519 密钥对
2. Bridge 发送 `connect` 消息，附带公钥和设备标识
3. Gateway 返回加密 challenge
4. Bridge 使用私钥签名 challenge
5. Gateway 验证签名 → 建立可信连接

### 设备配对 (可选)

```
Bridge → Gateway: device.pair.request
Gateway → Bridge (push): device.pair.approval_pending
App → Bridge → Gateway: device.pair.approve / device.pair.reject
```

### 网关 RPC 方法

| 方法 | 方向 | 描述 |
|------|------|------|
| `connect` | Bridge→Gateway | 认证连接 |
| `chat.send` | Bridge→Gateway | 发送 agent 执行请求；不得携带 `expectedArtifactDirs` |
| `agent.wait` | Bridge→Gateway | 等待 agent 完成 |
| `health` | Bridge→Gateway | 健康检查 |
| `skills.status` | Bridge→Gateway | 技能状态 |
| `channels.status` | Bridge→Gateway | 通道状态 |
| `models.list` | Bridge→Gateway | 模型列表 |
| `cron.list` | Bridge→Gateway | 定时任务列表 |
| `system-presence` | Bridge→Gateway | 系统在线状态 |
| `xworkmate.artifacts.prepare` | Bridge→Gateway→Plugin | 工件准备 |
| `xworkmate.artifacts.export` | Bridge→Gateway→Plugin | 工件导出 |
| `xworkmate.artifacts.list` | Bridge→Gateway→Plugin | 工件列表 |
| `xworkmate.artifacts.read` | Bridge→Gateway→Plugin | 工件读取 |

### 推送事件 (Gateway→Bridge)

| 事件 | 描述 |
|------|------|
| `chat.run` | Agent 执行进度事件 |
| `chat.error` | Agent 执行错误 |
| `health` | 网关健康状态 |
| `device.pair.approval_pending` | 设备配对请求 |
| `device.pair.update` | 设备配对状态变更 |

---

## 4. OpenClaw Gateway ↔ Plugin: 插件 API 边界

### 插件注册 (openclaw.plugin.json)

```json
{
  "name": "openclaw-multi-session-plugins",
  "version": "0.1.15",
  "openclaw": {
    "extensions": ["./dist/index.js"]
  },
  "gatewayMethods": [
    "xworkmate.tasks.get",
    "xworkmate.artifacts.prepare",
    "xworkmate.artifacts.export",
    "xworkmate.artifacts.collect-and-snapshot",
    "xworkmate.artifacts.list",
    "xworkmate.artifacts.read"
  ],
  "tools": {
    "openclaw_multi_session_artifacts": { "sessionScoped": true }
  },
  "config": {
    "workspaceDir": "~/.openclaw/workspace",
    "maxFiles": 1000,
    "maxInlineBytes": 1048576,
    "artifactRefSigningSecret": ""
  }
}
```

### 网关方法契约

| 方法 | 输入 | 输出 |
|------|------|------|
| `xworkmate.artifacts.prepare` | `{sessionKey, runId, workspaceDir?}` | `{artifactScope, artifactDirectory, scopeKind}` |
| `xworkmate.artifacts.export` | `{sessionKey, runId, artifactScope?, sinceUnixMs?, expectedArtifactDirs?}` | `{artifacts[], manifestMarkdown, warnings[]}` |
| `xworkmate.artifacts.collect-and-snapshot` | `{sessionKey, runId, artifactScope?, sinceUnixMs?, expectedArtifactDirs?}` | `{artifacts[], warnings[]}` |
| `xworkmate.artifacts.list` | `{sessionKey, runId, ...}` | `{artifacts[] (不含内容), manifestMarkdown}` |
| `xworkmate.artifacts.read` | `{sessionKey, runId, artifactScope?, relativePath?, artifactRef?}` | `{artifacts[0], manifestMarkdown}` |
| `xworkmate.tasks.get` | `{appThreadKey, openclawSessionKey, runId/taskId}` | `{taskStatus, status, artifacts[], warnings[]}` |

`expectedArtifactDirs` has a single upstream source:
`session.start.metadata.xworkmateTaskArtifactContract.expectedArtifactDirs`.
Bridge may pass it to artifact export/snapshot RPCs only. It is not accepted at
`session.start` root, metadata root, `chat.send`, or `xworkmate.tasks.get`.

### 安全边界

```
artifactRef = HMAC-SHA256(workspaceRoot, sessionKey, runId, relativePath, size, sha256)

验证条件:
  1. artifactRef 签名有效 (HMAC 密钥匹配)
  2. artifactRef 未过期 (24h TTL)
  3. path 在 workspaceRoot 内 (无路径穿越)
  4. path 非符号链接
  5. artifactScope 与 sessionKey/runId 匹配 (无跨会话借用)

跳过目录: .git, .openclaw, .xworkmate, node_modules
忽略文件: .gitignore, artifact-ignore.md 匹配
```

### Agent 工具边界

```
工具: openclaw_multi_session_artifacts
  输入: { action: "list"|"read", artifactScope?, relativePath? }
  输出: { artifacts[]|manifestMarkdown }
  安全: sessionKey/runId 由 OpenClaw 运行时注入,
        Agent 无法覆盖 (在 tool factory 中解构排除)
```

---

## 5. Plugin → Bridge 反向调用边界

该边界已移除。插件不得通过 HTTP 调用 xworkmate-bridge，也不再暴露
`xworkmate.agents.run` 或 `openclaw_multi_session_agents`。多 agent 编排由
OpenClaw 原生 runtime 或 xworkmate-bridge 自身拥有，插件只保留 artifact
scope、artifact manifest/read、task snapshot adapter 和 session key mapping。

---

## 6. 边界脆弱点汇总

| 边界 | 脆弱点 | 严重程度 |
|------|--------|---------|
| App↔Bridge | SSE 流中断 → 降级为轮询 | **中** |
| App↔Bridge | 120s 超时对长任务不够 | **中** |
| App↔Bridge | WebSocket 断线重连无消息队列持久化 | **中** |
| Bridge↔Provider | Gemini/Hermes 子进程崩溃 | **高** |
| Bridge↔Provider | Codex MCP 配置注入冲突 | **中** |
| Bridge↔Gateway | WebSocket 断连 → 任务状态丢失 | **高** |
| Bridge↔Gateway | Ed25519 密钥轮换无自动化 | **低** |
| Gateway↔Plugin | artifactRef 签名密钥不一致 | **高** |
| Gateway↔Plugin | 24h 签名过期 → 历史工件不可读 | **中** |
| Plugin→Bridge | 已移除；旧插件版本若残留会恢复循环依赖 | **高** |
| 全部 | 多仓库版本耦合 (app 1.1.4 + bridge latest + plugins 0.1.15) | **中** |
