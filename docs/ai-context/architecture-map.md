# Architecture Map — 跨仓库架构地图

> 生成日期: 2026-06-05 | 三个仓库的拓扑关系和协议边界

---

## 整体拓扑

```
┌─────────────────────────────────────────────────────────────┐
│                      用户桌面 (localhost)                      │
│                                                             │
│  ┌──────────────────────┐    ┌───────────────────────────┐  │
│  │   xworkmate-app       │    │   xworkmate-bridge         │  │
│  │   (Flutter/Dart)     │    │   (Go, :8787)              │  │
│  │                      │    │                           │  │
│  │ ┌──────────────────┐ │    │ ┌───────────────────────┐ │  │
│  │ │ AppController    │ │    │ │ HTTP/WS Handler       │ │  │
│  │ │ Desktop          │ │    │ │ /acp (WS)             │ │  │
│  │ └────────┬─────────┘ │    │ │ /acp/rpc (HTTP POST)  │ │  │
│  │          │            │    │ └───────────┬───────────┘ │  │
│  │ ┌────────▼─────────┐ │    │             │              │  │
│  │ │ GatewayRuntime   │ │◄───┼── ACP ──────┘              │  │
│  │ │ (WS + ACP Client)│ │    │ JSON-RPC 2.0              │  │
│  │ └────────┬─────────┘ │    │                           │  │
│  │          │            │    │ ┌───────────────────────┐ │  │
│  │ ┌────────▼─────────┐ │    │ │ Router                │ │  │
│  │ │ GoTaskService    │ │    │ │ (provider selection)  │ │  │
│  │ │ (任务分派)        │ │    │ └───────┬───────┬───────┘ │  │
│  │ └──────────────────┘ │    │         │       │          │  │
│  └──────────────────────┘    │    ┌────▼──┐ ┌──▼──────┐  │  │
│                              │    │ codex │ │ opencode│  │  │
│                              │    │(CLI)  │ │ (serve) │  │  │
│                              │    └───────┘ └─────────┘  │  │
│                              │    ┌───────┐ ┌─────────┐  │  │
│                              │    │ gemini│ │ hermes  │  │  │
│                              │    │(CLI)  │ │ (CLI)   │  │  │
│                              │    └───────┘ └─────────┘  │  │
│                              └─────────────┬─────────────┘  │
│                                            │                │
│                          ┌─────────────────┼────────────────┤
│                          │    OpenClaw 网关                 │
│                          │    (ws://127.0.0.1:18789)       │
│                          │    / openclaw.svc.plus:443      │
│                          └─────────────────┬───────────────┘
│                                            │
│                          ┌─────────────────▼───────────────┐
│                          │  openclaw-multi-session-plugins │
│                          │  (TypeScript, npm 插件)          │
│                          │                                 │
│                          │  网关方法:                       │
│                          │  xworkmate.artifacts.*           │
│                          │  xworkmate.agents.run            │
│                          │                                 │
│                          │  Agent 工具:                     │
│                          │  openclaw_multi_session_*        │
│                          └─────────────────────────────────┘
│                                                             │
└─────────────────────────────────────────────────────────────┘

                        云端服务

  ┌──────────────────┐    ┌──────────────────────────────┐
  │ accounts.svc.plus│    │ xworkmate-bridge.svc.plus     │
  │ (账户/MFA)        │    │ (托管 Bridge, 多租户)         │
  └──────────────────┘    └──────────────────────────────┘

  ┌──────────────────┐
  │ ollama.svc.plus   │
  │ ollama.com        │
  │ (LLM 推理)         │
  └──────────────────┘
```

---

## 协议边界

### 边界 1: App ↔ Bridge (ACP JSON-RPC)

| 属性 | 值 |
|------|-----|
| 协议 | JSON-RPC 2.0 |
| 传输 | WebSocket (`/acp`) + HTTP POST/SSE (`/acp/rpc`) |
| 认证 | Bearer token (BRIDGE_AUTH_TOKEN) |
| 方向 | App → Bridge (请求), Bridge → App (SSE 推送) |
| 关键方法 | `session.start`, `session.message`, `acp.capabilities`, `xworkmate.gateway.*` |

### 边界 2: Bridge ↔ AI Providers (ACP JSON-RPC)

| 属性 | 值 |
|------|-----|
| 协议 | JSON-RPC 2.0 |
| 传输 | WebSocket (codex) / HTTP (opencode, gemini, hermes) |
| 认证 | Bearer token |
| 方向 | Bridge → Provider (请求/响应) |
| 特殊 | gemini/hermes 通过子进程 stdio 中转（adapter 模式） |

### 边界 3: Bridge ↔ OpenClaw Gateway (Gateway RPC)

| 属性 | 值 |
|------|-----|
| 协议 | 自定义 WebSocket RPC（Ed25519 加密握手） |
| 传输 | WebSocket |
| 默认端点 | `ws://127.0.0.1:18789` (本地) / `wss://openclaw.svc.plus:443` (云端) |
| 关键方法 | `chat.send`, `xworkmate.artifacts.*`, `agent.wait` |
| 方向 | 双向 (Bridge 发起请求 + 订阅推送事件) |

### 边界 4: OpenClaw Gateway ↔ Plugin (内部插件 API)

| 属性 | 值 |
|------|-----|
| 协议 | OpenClaw Plugin SDK (内存调用) |
| 方法 | `xworkmate.artifacts.prepare/export/list/read`, `xworkmate.agents.run` |
| 工具 | `openclaw_multi_session_artifacts`, `openclaw_multi_session_agents` |

---

## 数据流方向

```
用户输入
  │
  ▼
xworkmate-app ──── session.start ────► xworkmate-bridge
  │                                        │
  │                                        ├──► codex/opencode/gemini/hermes
  │                                        │       (AI agent 执行)
  │                                        │
  │                                        └──► OpenClaw Gateway
  │                                                │
  │                                   chat.send     │
  │                                   ◄─────────────┘
  │  SSE stream (token by token)
  │  xworkmate.gateway.push
  ◄─────────────────────────────────
  │
  │  工件下载:
  │  GET /artifacts/openclaw/download?ref=<signed>
  ├──────────────────────────────────► xworkmate-bridge
  │                                        │
  │                                        └──► xworkmate.artifacts.read
  │                                                │
  │                                                ▼
  │                                     openclaw-multi-session-plugins
  │
  ▼
本地文件: ~/.xworkmate/threads/<session>/
```

---

## 关键配置项

### xworkmate-app (config/settings.yaml)
```yaml
bridge:
  server_url: "https://xworkmate-bridge.svc.plus"
  auth_token: ""

accounts:
  base_url: "https://accounts.svc.plus"
```

### xworkmate-bridge (环境变量 / config.yaml)
```yaml
upstream:
  gateway_url: "ws://127.0.0.1:18789"     # GATEWAY_RPC_URL
  codex_url: ""                           # CODEX_RPC_URL
  opencode_url: "http://127.0.0.1:38993"  # OPENCODE_RPC_URL
  gemini_url: "http://127.0.0.1:8791"     # GEMINI_RPC_URL
  hermes_url: "http://127.0.0.1:3920"     # HERMES_RPC_URL

distributed_nodes:
  - id: xworkmate-bridge
    role: primary
    endpoint: "http://172.29.10.1:8787"
  - id: cn-xworkmate-bridge
    role: edge
    endpoint: "http://172.29.10.2:8787"
```

### openclaw-multi-session-plugins (openclaw.plugin.json)
```json
{
  "gatewayMethods": [
    "xworkmate.artifacts.prepare",
    "xworkmate.artifacts.export",
    "xworkmate.artifacts.list",
    "xworkmate.artifacts.read",
    "xworkmate.agents.run"
  ],
  "config": {
    "bridgeUrl": "",
    "bridgeToken": "",
    "workspaceDir": "~/.openclaw/workspace",
    "maxFiles": 1000,
    "artifactRefSigningSecret": ""
  }
}
```
