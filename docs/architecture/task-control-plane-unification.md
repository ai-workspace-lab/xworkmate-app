# 任务执行链路统一收敛

Last Updated: 2026-04-08

## 背景

当前仓库里已经存在 `GoTaskService`、Go ACP `Router.Resolve`、`Skills.Resolve`、
`Memory` 与 `buildResolvedExecutionParams`，说明统一控制面已经具备核心骨架。

但旧设计文档长期把不同实现通道写成并列主链，导致：

- Desktop / Web / Mobile 的现状与目标混在一起
- controller 层的历史分流被误认为长期规范
- `gateway` 与显式 `multi-agent` 被描述成 UI 规范入口

本文件把官方口径统一为：

- UI 不变
- `GoTaskService.executeTask` 是唯一公开入口
- ACP 是统一控制面
- `bridge` 是 app 客户端的发现 / 配置 / 连接 / 对话枢纽
- 账户同步只同步 bridge 相关配置属性与安全引用，不做自动连接


## 目标态
```mermaid
flowchart TD
    A["Desktop / Web / Mobile UI"] --> B["sendMessage<br/>统一 Task Envelope"]
    B --> C["GoTaskService.executeTask<br/>唯一公开入口"]
    C --> D["ACP.session.start / session.message"]
    D --> E["Router.Resolve"]
    E --> F["Skills.Resolve"]
    F --> G["Memory.Inject"]
    G --> H["buildResolvedExecutionParams"]
    H --> I{"resolvedExecutionTarget"}
    I -->|"single-agent"| J["single-agent ACP request"]
    I -->|"multi-agent"| K["multi-agent ACP request"]
    J --> M["bridge hub"]
    K --> M
    M --> N["Gateway / Provider adapters"]
    N --> O["stream events / result"]
    O --> P["Memory.Record"]
    P --> Q["Update Thread State"]
    Q --> R["UI stream render"]
```

## Provider 真源

Single-agent provider catalog and availability are owned by
`xworkmate-bridge`, not by local endpoint presets inside the app.

```mermaid
flowchart TD
  A["Settings UI
  仅管理 Bridge 连接参数
  与自定义 upstream sync 定义"] --> B["SettingsSnapshot.externalAcpEndpoints
  仅作为 sync 输入"]

  B --> C["buildExternalAcpSyncedProvidersInternal()"]
  C --> D["syncExternalAcpProvidersInternal()"]
  D --> E["xworkmate.providers.sync"]
  E --> F["xworkmate-bridge providerCatalog"]

  F --> G["acp.capabilities"]
  G --> H["providers[]
  singleAgent / multiAgent"]

  H --> I["refreshSingleAgentCapabilitiesRuntimeInternal()"]
  I --> J["bridgeAdvertisedProvidersInternal
  App 内唯一 provider 名单源"]
  I --> K["singleAgentCapabilitiesByProviderInternal
  App 内唯一 provider 可用性源"]

  G --> L["refreshAcpCapabilitiesRuntimeInternal()"]
  L --> M["GatewayAcpCapabilities
  providers / singleAgent / multiAgent"]
  M --> N["mergeAcpCapabilitiesIntoMountTargetsRuntimeInternal()"]
  N --> O["ManagedMountTargetState
  codex / opencode / claude / gemini / aris / openclaw
  available / discoveryState"]

  J --> P["configuredSingleAgentProviders
  = bridgeAdvertisedProvidersInternal"]
  P --> Q["singleAgentProviderOptions
  Composer / Thread Picker 唯一数据源"]

  K --> R["availableSingleAgentProviders
  = bridge 当前可用 provider"]
  R --> S["visibleAssistantExecutionTargets(...)
  single-agent 是否显示
  只看 runtime available providers"]

  O --> T["visible gateway / multi-agent execution affordances
  openclaw / aris discovery 只看 bridge capabilities"]

  Q --> U["setSingleAgentProvider(providerId)
  仅写入 thread executionBinding.providerId"]

  U --> V["singleAgentProviderForSession()
  恢复线程已选 providerId"]

  V --> W["sendSingleAgentMessageDesktopGoTaskFlowInternal()"]
  W --> X["再次拉取 acp.capabilities"]
  X --> Y["按本次 bridge providers 解析
  auto -> 当前 bridge 顺序第一个可用 provider
  explicit -> 当前 bridge 已广告的 provider"]

  Y --> Z{"provider resolved?"}
  Z -->|"yes"| AA["executeTask(... provider ...)"]
  Z -->|"no"| AB["provider unavailable UX"]
```

## 端侧桥接规则

### Desktop App

- Desktop App 直接桥接 Go 代码
- Desktop 正常执行链路不以“先启动一个本地 HTTP server，再由 Desktop 自己回连”作为目标架构
- Desktop 的 `sendMessage -> GoTaskService.executeTask -> ACP` 应理解为进程内或直接桥接语义
- 对 app 来说，bridge 是 discovery / config / connect / dialogue 的统一枢纽

### Web / Mobile

- Web / Mobile UI 连接的是 Go 代码启动出来的 server
- Web / Mobile 通过标准 ACP contract 与该 server 通信
- 对 Web / Mobile 来说，`/acp` 与 `/acp/rpc` 是稳定的网络协议入口

## 协议约束

### 传输协议

- local / loopback 允许 `ws://` 或 `http://`
- remote 必须使用 `wss://` 或 `https://`
- remote 模式禁止静默降级到非 TLS

### ACP contract

- websocket endpoint 规范路径：`/acp`
- RPC endpoint 规范路径：`/acp/rpc`
- base URL 派生时必须避免重复拼接 `/acp`
- 以上 endpoint contract 主要适用于 Web / Mobile 与外部 ACP server 的通信语义
- Desktop 目标态不要求为自身 UI 再额外启动一层本地 HTTP ACP server

## 收敛原则

### Current implementation note

- 当前实现可能仍残留历史分流代码
- 这些实现痕迹不再代表规范

### Target architecture rule

- 所有正常发送请求都先进入 `GoTaskService.executeTask`
- 所有任务都先进入 ACP 控制面，再解析到 executor
- Desktop 采用直接桥接 Go 代码的控制面接入方式
- Web / Mobile 采用连接 Go server 的控制面接入方式

### Compatibility route (removed from target)

- `openClawTask` 不再属于目标架构
- `GatewayRuntime`、`Web relay`、`GatewayAcpClient` 只作为 adapter/executor 能力存在

## 分阶段方向

1. 文档口径收敛
2. Dart 请求模型统一
3. route 决策内收到 `GoTaskService` / ACP
4. app 侧 bridge 枢纽与 provider / gateway 适配关系收敛
5. `multi-agent` 成为统一请求语义
