# Chain Map — 跨仓库调用链

> 生成日期: 2026-06-05 | 文件级调用链，标注协议边界

---

## Chain 1: 用户发起 AI 对话 (主流程)

```
xworkmate-app                                    xworkmate-bridge
─────────────                                    ────────────────
lib/app/app_controller_desktop.dart
  → handleChatSend()
    └─ lib/runtime/gateway_runtime_core.dart
         GatewayRuntime.sendMessage()
           │
           ├── (ACP WebSocket 路径)
           │   └─ lib/runtime/gateway_acp_client.dart
           │        GatewayAcpClient.request(method: "session.start", ...)
           │          → WebSocket /acp ──────────────────► internal/acp/http_handler.go
           │                                                HandleWebSocket()
           │                                                  └─ internal/acp/rpc_handler.go
           │                                                       handleRequest("session.start", ...)
           │                                                         └─ internal/router/
           │                                                              Resolve(provider)
           │                                                                └─ Provider handler
           │
           └── (ACP HTTP/SSE 路径)
               └─ lib/runtime/gateway_acp_client.dart
                    GatewayAcpClient.request()
                      → HTTP POST /acp/rpc ──────────────► internal/acp/http_handler.go
                                                             HandleRPC()
                                                               └─ internal/acp/rpc_handler.go
                                                                    handleRequest(...)
```

### 涉及的 key files:
| 层 | 文件 | 作用 |
|----|------|------|
| app | `lib/app/app_controller_desktop.dart` | 用户输入入口 |
| app | `lib/runtime/gateway_runtime_core.dart` | Gateway runtime 核心 |
| app | `lib/runtime/gateway_acp_client.dart` | ACP 客户端 (JSON-RPC 封装) |
| app | `lib/runtime/acp_endpoint_paths.dart` | 端点路径解析 |
| bridge | `internal/acp/http_handler.go` | HTTP/WS 请求入口 |
| bridge | `internal/acp/rpc_handler.go` | JSON-RPC 方法分发 |
| bridge | `internal/router/` | 提供商路由 |

### 协议: ACP JSON-RPC 2.0 over WebSocket (主) / HTTP SSE (后备)
### 断点风险:
- ACP 客户端 120s 超时 → 长任务可能超时
- SSE 流中断后降级为轮询 (`xworkmate.tasks.get`)
- WebSocket 断线需重连 (30s ping/10s 超时)

---

## Chain 2: OpenClaw 网关任务执行

```
xworkmate-app                                    xworkmate-bridge
─────────────                                    ────────────────
lib/runtime/external_code_agent_acp_desktop_transport.dart
  ExternalCodeAgentAcpTransport
    → session.start(provider="gateway")
      └─ lib/runtime/gateway_acp_client.dart
           → POST /gateway/openclaw ────────────────► internal/acp/http_handler.go
           │                                            HandleOpenClawRPC()
           │                                              └─ internal/acp/gateway.go
           │                                                   Orchestrator.Process()
           │                                                     │
           │                                                     ├─ 本地 gateway
           │                                                     │   └─ internal/gatewayruntime/runtime.go
           │                                                     │        GatewayRuntime.Connect()
           │                                                     │          → WebSocket ────► OpenClaw Gateway
           │                                                     │                              ws://127.0.0.1:18789
           │                                                     │                                │
           │                                                     │                                ├─ chat.send
           │                                                     │                                ├─ agent.wait
           │                                                     │                                └─ xworkmate.artifacts.*
           │                                                     │                                      │
           │                                                     │                                      ▼
           │                                                     │                           openclaw-multi-session-plugins
           │                                                     │                           ─────────────────────────────
           │                                                     │                           index.ts → register()
           │                                                     │                             xworkmate.artifacts.prepare
           │                                                     │                             xworkmate.artifacts.export
           │                                                     │                             xworkmate.artifacts.read
           │                                                     │
           │                                                     └─ 分布式转发
           │                                                         └─ internal/acp/distributed_forwarder.go
           │                                                              ForwardToPeer()
           │                                                                → HTTP POST → 远端 bridge /acp/rpc
           │
           ◄── SSE stream (token by token) ────────────
           ◄── xworkmate.gateway.push (chat events) ───

lib/app/app_controller_openclaw_task_queue.dart
  OpenClawTaskQueue
    → 本地队列管理 (max 5 active, 20 queued)
    → 持久化 & 恢复 (pollOpenClawTaskAssociationInternal)
```

### 涉及的 key files:
| 层 | 文件 | 作用 |
|----|------|------|
| app | `lib/runtime/external_code_agent_acp_desktop_transport.dart` | 任务传输层 |
| app | `lib/runtime/go_task_service_client.dart` | 任务接口定义 |
| app | `lib/runtime/go_task_service_desktop_service.dart` | 桌面任务服务 |
| app | `lib/app/app_controller_openclaw_task_queue.dart` | 客户端任务队列 |
| bridge | `internal/acp/gateway.go` | OpenClaw 集成 |
| bridge | `internal/acp/http_handler.go` | `/gateway/openclaw` 端点 |
| bridge | `internal/gatewayruntime/runtime.go` | 网关 WS 客户端 |
| bridge | `internal/acp/distributed_forwarder.go` | 分布式转发 |
| plugins | `index.ts` | 插件入口 |
| plugins | `src/exportArtifacts.ts` | 工件逻辑 |

### 协议: ACP JSON-RPC → Gateway RPC (WebSocket, Ed25519 握手)
### 断点风险:
- 网关 WebSocket 断连 → 任务丢失
- 分布式转发 hop=3 限制 → 深层拓扑不可达
- 任务轮询恢复依赖 `xworkmate.tasks.get` → 非实时

---

## Chain 3: 工件下载流

```
xworkmate-app                                    xworkmate-bridge
─────────────                                    ────────────────
lib/app/app_controller_desktop_thread_storage.dart
  syncArtifactsFromBridge()
    → GET /artifacts/openclaw/download ───────────► internal/acp/http_handler.go
           ?ref=<signed>&t=<expiry>                  HandleArtifactDownload()
                                                       └─ internal/gatewayruntime/runtime.go
                                                            gateway.RequestByMode(
                                                              "openclaw",
                                                              "xworkmate.artifacts.read",
                                                              params
                                                            )
                                                              │
                                                              ▼
                                                    openclaw-multi-session-plugins
                                                    ─────────────────────────────
                                                    src/exportArtifacts.ts
                                                      xworkmate.artifacts.read()
                                                        → 验证 HMAC 签名
                                                        → 读取文件内容
                                                        → 返回 artifact
```

### 涉及的 key files:
| 层 | 文件 | 作用 |
|----|------|------|
| app | `lib/app/app_controller_desktop_thread_storage.dart` | 工件同步 |
| bridge | `internal/acp/http_handler.go` | 下载端点 |
| bridge | `internal/gatewayruntime/runtime.go` | 网关调用 |
| plugins | `src/exportArtifacts.ts` | read 逻辑 |

### 安全: HMAC-SHA256 签名绑定 (workspaceRoot, session, run, path, size, hash)
### 断点风险:
- 签名过期 (24h) → 下载失败
- 签名密钥不一致 → 验证失败

---

## Chain 4: MCP 配置生成

```
xworkmate-app                                    xworkmate-bridge
─────────────                                    ────────────────
lib/runtime/codex_config_bridge.dart
  CodexConfigBridge.generate()
    → 写入 ~/.codex/config.toml
      [mcp_servers.xworkmate]
      command = "openclaw-mcp"
      args = ["--gateway", "https://xworkmate-bridge.svc.plus"]
      # BEGIN XWORKMATE MANAGED MCP BLOCK
      ...
      # END XWORKMATE MANAGED MCP BLOCK

lib/runtime/opencode_config_bridge.dart
  OpencodeConfigBridge.generate()
    → 写入 ~/.opencode/config.toml
      [mcp_servers.xworkmate]
      url = "https://xworkmate-bridge.svc.plus/acp"
      # 或 type="stdio" + command="openclaw-mcp" + args=["--gateway", url]
```

### 涉及的 key files:
| 层 | 文件 | 作用 |
|----|------|------|
| app | `lib/runtime/codex_config_bridge.dart` | Codex CLI 配置 |
| app | `lib/runtime/opencode_config_bridge.dart` | OpenCode CLI 配置 |
| bridge | `internal/mounts/reconcile.go` | MCP 配置管理 (服务端) |

### 断点风险:
- 配置 block 标记 (`# BEGIN XWORKMATE MANAGED MCP BLOCK`) 冲突 → 覆盖用户配置
- Gateway URL 变更 → 需重新生成配置

---

## Chain 5: 多 Agent 编排 (Plugin → Bridge 反向调用)

```
openclaw-multi-session-plugins                   xworkmate-bridge
─────────────────────────────                    ────────────────
src/bridgeAgents.ts
  run(input)
    → fetch(bridgeUrl, {
        method: "POST",
        body: { jsonrpc: "2.0",
                method: "session.start",
                params: {
                  sessionId: "openclaw:<sessionKey>",
                  multiAgent: true,
                  mode: "multi-agent",
                  routing: { orchestrationMode, steps, ... }
                }
              }
      })
      → HTTP POST /acp/rpc ──────────────────────► internal/acp/rpc_handler.go
                                                      handleRequest("session.start", ...)
                                                        └─ internal/router/
                                                             → Orchestrator.Process()
                                                               → 多 agent 协作
                                                               → 结果返回插件

src/exportArtifacts.ts
  → 结果写入 artifactDirectory
    → multi-agent-result.json
    → multi-agent-result.md
```

### 涉及的 key files:
| 层 | 文件 | 作用 |
|----|------|------|
| plugins | `src/bridgeAgents.ts` | Bridge HTTP 调用 |
| bridge | `internal/acp/rpc_handler.go` | RPC 分发 |
| bridge | `internal/acp/orchestrator.go` | 多 agent 编排 |

### 协议: HTTP JSON-RPC (插件 → Bridge)
### 断点风险:
- 插件配置中 bridgeUrl 指向错误 → 调用失败
- 双向循环依赖: plugins 调 bridge, bridge 调 plugins

---

## 跨仓库调用矩阵

```
                    调用方
                app    bridge    plugins
              ┌───────┬───────┬───────┐
      app     │   -   │ ACP   │   -   │
被调   bridge  │   -   │  -    │ HTTP  │
方    plugins │   -   │ GW    │   -   │
              └───────┴───────┴───────┘

ACP  = JSON-RPC 2.0 over WebSocket/HTTP SSE
HTTP = JSON-RPC 2.0 over HTTP POST
GW   = OpenClaw Gateway RPC over WebSocket (Ed25519)
```

## 调用链复杂度评分

| Chain | 跨仓库跳数 | 协议变换 | 风险等级 |
|-------|-----------|---------|---------|
| Chain 1 (AI 对话) | 2 (app→bridge→provider) | 1 (ACP) | **中** |
| Chain 2 (OpenClaw 任务) | 4 (app→bridge→gateway→plugins) | 2 (ACP + GW RPC) | **高** |
| Chain 3 (工件下载) | 3 (app→bridge→gateway→plugins) | 2 (HTTPS + GW RPC) | **中** |
| Chain 4 (MCP 配置) | 1 (app→本地文件) | 0 | **低** |
| Chain 5 (多 Agent) | 2 (plugins→bridge→provider) + 2 (bridge→gateway→plugins) | 2 (HTTP + GW RPC) | **高/循环** |
