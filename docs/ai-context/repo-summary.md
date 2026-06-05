# Repo Summary — 三个仓库核心职责

> 生成日期: 2026-06-05 | 基于目录结构、README、依赖清单、入口文件、配置文件

---

## 1. xworkmate-app (Flutter/Dart)

### 核心职责
XWorkmate 桌面客户端 — AI 协作工具的 GUI 前端。负责用户交互、会话管理、配置生成、任务队列。

### 入口模块
| 入口 | 路径 | 作用 |
|------|------|------|
| main | `lib/main.dart` | 加载 FeatureManifest，启动 XWorkmateApp |
| app | `lib/app/app.dart` | 顶层 Widget 树 |
| controller | `lib/app/app_controller_desktop.dart` | 桌面版主控制器（所有平台逻辑入口） |

### 关键目录
```
lib/
  app/          — 应用级编排 (controller, gateway, runtime helpers, task queue)
  runtime/      — 服务层: ACP 客户端、Gateway runtime、Account client、任务服务
  features/     — UI 特性模块 (按功能拆分)
  models/       — 数据模型
  widgets/      — 可复用组件
  i18n/         — 国际化
config/
  settings.yaml         — 默认服务 URL 配置
  feature_flags.yaml    — 功能开关
```

### 主要调用链
```
GUI Event
  → AppControllerDesktop
    → GatewayRuntime (.connect, .chat, .session)
      → GatewayAcpClient (JSON-RPC 2.0)
        → HTTP POST /acp/rpc  或  WebSocket /acp
          → xworkmate-bridge

GUI Event
  → GoTaskServiceClient (DesktopGoTaskService)
    → ExternalCodeAgentAcpTransport
      → GatewayAcpClient (.session.start / .session.message)
        → xworkmate-bridge

配置生成
  → CodexConfigBridge / OpencodeConfigBridge
    → 写入 ~/.codex/config.toml / ~/.opencode/config.toml
    → 注入 MCP server 配置 (openclaw-mcp --gateway <url>)
```

### 与其他仓库的关系
- **xworkmate-bridge**: 通过 ACP JSON-RPC (HTTP/SSE/WebSocket) 通信。是 app 的唯一上游。
- **openclaw-multi-session-plugins**: 不直接通信。通过 bridge 中转。
- **openclaw.svc.plus** / **accounts.svc.plus**: REST/WebSocket 外部服务。

### 技术栈
Dart/Flutter, `http` 包, `web_socket_channel`, `flutter_webrtc`, 无 gRPC 依赖。

---

## 2. xworkmate-bridge (Go)

### 核心职责
ACP 控制平面网关 — 连接 Flutter 前端与多个 AI agent 后端的中间层。负责协议适配、路由、分布式转发、工件管理和 WebRTC 桌面流。

### 入口模块
| 入口 | 路径 | 作用 |
|------|------|------|
| main | `main.go` | CLI 入口 (`serve` / `adapter` / `stdio` / `version`) |
| serve cmd | `cmd/` | `serve` 命令启动 HTTP/WS 服务器 |
| http handler | `internal/acp/http_handler.go` | 路由注册 (所有端点) |
| rpc handler | `internal/acp/rpc_handler.go` | JSON-RPC 方法分发 |

### 关键目录
```
internal/
  acp/              — ACP 协议实现 (HTTP handler, RPC handler, gateway, config)
  router/           — 提供商路由决策引擎
  gatewayruntime/   — OpenClaw 网关 WebSocket 客户端
  geminiadapter/    — Gemini CLI stdio 适配器
  hermesadapter/    — Hermes CLI stdio 适配器
  opencodeadapter/  — OpenCode HTTP 适配器
  mounts/           — 提供商 MCP 配置管理
main.go             — 入口
Dockerfile          — 容器化部署
```

### 主要调用链
```
xworkmate-app
  → POST /acp/rpc (session.start)
    → rpc_handler.handleRequest()
      → router.Resolve(provider)
        → codex:     WebSocket/HTTP → codex endpoint
        → opencode:  HTTP → 127.0.0.1:38993 (opencode serve 子进程)
        → gemini:    HTTP → 127.0.0.1:8791 (gemini adapter 子进程)
        → hermes:    HTTP → 127.0.0.1:3920 (hermes adapter 子进程)
        → openclaw:  WebSocket → OpenClaw gateway (ws://127.0.0.1:18789)

xworkmate-app
  → /acp or /acp/rpc session.start (routing: gateway/openclaw)
    metadata.xworkmateTaskArtifactContract.expectedArtifactDirs
    → acp/rpc_handler.go → orchestrator.go → gatewayruntime/runtime.go
      → WebSocket → OpenClaw gateway
        → chat.send → agent 执行 (no expectedArtifactDirs root field)
        → xworkmate.artifacts.export/collect-and-snapshot
          with expectedArtifactDirs from the artifact contract
        → openclaw-multi-session-plugins
```

### 与其他仓库的关系
- **xworkmate-app**: 被调用方。暴露 `/acp` (WS) 和 `/acp/rpc` (HTTP) 端点。
- **openclaw-multi-session-plugins**: 通过 OpenClaw 网关 RPC 间接调用（`xworkmate.artifacts.*`）。
- **openclaw.svc.plus**: WebSocket 连接目标（生产网关）。

### 技术栈
Go 1.25, gorilla/websocket, pion/webrtc v4, YAML 配置。无 gRPC。Docker 部署。

---

## 3. openclaw-multi-session-plugins (TypeScript)

### 核心职责
OpenClaw 插件 — XWorkmate artifact 作用域适配层。为每个 session/run 对创建隔离工件目录，扫描文件，生成 HMAC 签名引用，并把 task snapshot 与 OpenClaw 原生 task/session 状态对齐。

### 入口模块
| 入口 | 路径 | 作用 |
|------|------|------|
| plugin entry | `index.ts` | register() — 注册 task/artifact 网关方法 + artifact agent 工具 |
| artifacts | `src/exportArtifacts.ts` | 工件准备/导出/读取逻辑 |
| manifest | `openclaw.plugin.json` | 声明网关方法和工具配置 |

### 关键目录
```
src/
  exportArtifacts.ts  — 核心: prepare/export/list/read
  taskState.ts        — task snapshot + session key mapping adapter
index.ts              — 插件入口: register()
openclaw.plugin.json  — 插件清单: 网关方法 + 工具声明
```

### 主要调用链
```
OpenClaw 网关 (WebSocket RPC)
  → xworkmate.tasks.get         → 原生 task registry 状态 + artifact manifest
  → xworkmate.artifacts.prepare → 创建 tasks/<session>/<run>/ 目录
  → xworkmate.artifacts.export  → 扫描文件, 计算 HMAC 签名, 输出清单
  → xworkmate.artifacts.collect-and-snapshot → 收集 tool 输出并绑定到当前 artifact scope
  → xworkmate.artifacts.read    → 返回单个工件内容
```

### 与其他仓库的关系
- **xworkmate-bridge**: 被 bridge 通过 OpenClaw 网关 RPC 间接调用（`xworkmate.tasks.get`, `xworkmate.artifacts.*`）。
- **xworkmate-app**: 不直接通信。app 通过 bridge 的 `/artifacts/openclaw/download` 获取工件。

### 技术栈
TypeScript (ESM), Node.js, OpenClaw Plugin SDK。无外部 HTTP 依赖。
