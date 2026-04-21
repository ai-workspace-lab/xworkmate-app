# xworkmate-bridge 统一路由架构文档

## 1. 架构概览 (Unified Routing Architecture)

当前系统采用 `xworkmate-bridge.svc.plus` 作为统一入口。App 侧只通过 managed bridge ACP 主入口发送任务，provider / gateway 的 public mapping 由 bridge 后端拥有。

```mermaid
graph TD
    subgraph "External Access"
        Client["xworkmate-app (Client)"]
    end

    subgraph "Unified Gateway (Caddy)"
        Bridge_Domain["https://xworkmate-bridge.svc.plus"]
    end

    subgraph "Bridge-owned Routing"
        ManagedBridge["Managed Bridge ACP<br/>/acp/rpc"]
        CodexProvider["Codex map<br/>/acp-server/codex"]
        OpenCodeProvider["OpenCode map<br/>/acp-server/opencode"]
        GeminiAdapter["Gemini map<br/>/acp-server/gemini"]
        OpenClawGateway["OpenClaw map<br/>/gateway/openclaw"]
    end

    %% Routing Rules
    Client -->|HTTPS/WSS| Bridge_Domain

    Bridge_Domain -->|/acp/rpc| ManagedBridge
    ManagedBridge -->|provider routing| CodexProvider
    ManagedBridge -->|provider routing| OpenCodeProvider
    ManagedBridge -->|provider routing| GeminiAdapter
    ManagedBridge -->|gateway routing| OpenClawGateway

    %% Service Connections
    ManagedBridge -.->|Capabilities Discovery| Client
```

## 2. 路由分发规则

| Bridge-owned mapping | App 侧行为 | 备注 |
| :--- | :--- | :--- |
| `/acp/rpc` | 直接调用 | Managed Bridge ACP 主入口，提供能力发现与任务发送 |
| `/acp-server/codex` | 不直连 | Bridge 后端映射至 Codex Provider |
| `/acp-server/opencode` | 不直连 | Bridge 后端映射至 OpenCode Provider |
| `/acp-server/gemini` | 不直连 | Bridge 后端映射至 Gemini Adapter |
| `/gateway/openclaw` | 不直连 | Bridge 后端映射至 OpenClaw Gateway |

## 3. 运维配置优化

### 3.1 统一鉴权
App 发往 `xworkmate-bridge.svc.plus/acp/rpc` 的请求必须携带：
- **Header**: `Authorization: Bearer <bridge-auth-token>`
- **未授权响应**: `401 Unauthorized`

### 3.2 SSE / WebSocket 优化
所有反向代理均配置了 `flush_interval -1`，禁用了响应缓冲，以支持低延迟的 SSE 流式输出和稳定的 WebSocket 长连接。

### 3.3 日志持久化 (Docker)
`xworkmate-bridge-managed` 容器已配置日志挂载：
- **宿主机路径**: `/var/log/xworkmate-bridge/`
- **容器路径**: `/app/logs`
- **轮转策略**: 单文件 50MB，保留最近 3 个文件。

## 4. App 侧不变量

- App 不写入或拼接本地 provider endpoint。
- App 不直接调用 `/acp-server/*` 或 `/gateway/openclaw`。
- `acp.capabilities` 是 provider catalog、gateway catalog、available execution targets 的唯一来源。
