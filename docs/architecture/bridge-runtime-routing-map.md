# Bridge Runtime Routing Map

Last Updated: 2026-04-21

本文记录 `xworkmate-app` 当前对 `xworkmate-bridge` 的运行时路由合同。UI 不直接承载这些路径；Assistant UI 仍由 `acp.capabilities` 返回的 `providerCatalog`、`gatewayProviders`、`availableExecutionTargets` 驱动。

App 侧任务发送默认调用 bridge 主入口 `/acp/rpc`，不再拼接 provider-specific 直连 URL。OpenClaw `session.start` 和同一任务的 `session.message` 是唯一例外，使用 bridge 公开的 task submit 专用路径 `/gateway/openclaw`。该路径不是全局 ACP base endpoint。

## App Runtime Flow

```mermaid
flowchart TD
  A["Assistant send"] --> B["acp.capabilities"]
  B --> C["providerCatalog"]
  B --> D["gatewayProviders"]
  B --> E["availableExecutionTargets"]

  C --> F["Hermes"]
  C --> G["Codex"]
  C --> H["OpenCode"]
  C --> I["Gemini"]
  D --> J["OpenClaw"]

  A --> P["POST https://xworkmate-bridge.svc.plus/acp/rpc"]
  A --> T["OpenClaw task POST /gateway/openclaw"]
  P --> Q["Authorization: Bearer token"]
  T --> Q
  P --> R["provider / requestedExecutionTarget params"]
  T --> R
  R --> S["bridge-owned routing"]

  S --> K["Hermes internal runtime"]
  S --> L["Codex internal runtime"]
  S --> M["OpenCode internal runtime"]
  S --> N["Gemini internal runtime"]
  S --> O["OpenClaw internal runtime"]
```

## Routing Rules

- App runtime control-plane requests, agent tasks, multi-agent tasks, `session.cancel`, and `session.close` use `https://xworkmate-bridge.svc.plus/acp/rpc`.
- OpenClaw gateway `session.start` and follow-up `session.message` use `https://xworkmate-bridge.svc.plus/gateway/openclaw`.
- Provider and gateway selection are passed as request params, including `provider`, `routing`, and `requestedExecutionTarget`.
- Bridge-owned internal routing is opaque to the App; it is not represented as public provider paths.
- The app must not route managed bridge tasks to local or LAN endpoints such as `127.0.0.1:*` or `192.168.*:*`.
- The app must not route managed bridge tasks by directly constructing `/acp-server/*` URLs.
- `/gateway/openclaw` is allowed only for OpenClaw task submit; it must not be reused for capabilities, routing, gateway control-plane, cancel, close, or as an ACP base endpoint.
