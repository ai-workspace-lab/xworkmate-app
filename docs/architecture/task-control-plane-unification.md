# Task Control Plane Unification

Last Updated: 2026-04-13

## Background

当前 `xworkmate-app` 的主链已经不是“多模块并列入口”模型，而是：

- shell 只保留 `assistant + settings`
- assistant 负责线程、任务、结果与 bridge task/runtime 主链
- settings 负责 bridge connection、account sync、integration affordance
- app 不再维护本地 provider preset、旧 gateway 直连叙述、模块页矩阵

本文件定义的统一口径是：

- app 内任务入口统一走 `GoTaskService.executeTask`
- bridge capability / routing / gateway runtime 由 `xworkmate-bridge` 提供
- app 只消费 bridge 合同，不重建第二套 provider/gateway 真源

## Canonical Mainline

```mermaid
flowchart TD
    subgraph APP["xworkmate-app"]
        A1["AssistantPage"]
        A2["SettingsPage"]
        A3["AppControllerDesktop*"]
        A4["GoTaskService.executeTask"]
        A5["GatewayAcpClient / ExternalCodeAgentAcpDesktopTransport"]
        A1 --> A3
        A2 --> A3
        A3 --> A4
        A3 --> A5
    end

    subgraph CONTRACT["Bridge-facing contract"]
        B1["acp.capabilities"]
        B2["xworkmate.routing.resolve"]
        B3["session.start / session.message / session.cancel / session.close"]
        B4["xworkmate.gateway.connect / request / disconnect"]
    end

    subgraph BRIDGE["xworkmate-bridge"]
        C1["bridge-owned provider catalog"]
        C2["bridge-owned routing"]
        C3["bridge-owned gateway runtime"]
        C4["upstream ACP and gateway adapters"]
    end

    subgraph RETURN["Return path"]
        D1["stream events / runtime state"]
        D2["thread/session state update"]
        D3["assistant render / settings status"]
    end

    A4 --> B2
    A4 --> B3
    A5 --> B1
    A5 --> B4
    B1 --> C1
    B2 --> C2
    B3 --> C2
    B4 --> C3
    C1 --> C4
    C2 --> C4
    C3 --> C4
    C4 --> D1 --> D2 --> D3
```

## App-Side Truth Sources

### Surface Truth

- `feature_flags.yaml -> UiFeatureManifest / AppCapabilities -> Shell / Registry` 是唯一 surface 事实源
- app 不再把 provider topology、gateway backend、旧模块入口写成 shell 级分类

### Provider Truth

- `acp.capabilities.providerCatalog` 是 assistant provider picker 的唯一上游真源
- 持久化在线程上的 `providerId` 只表示用户历史选择，不负责反向生成 catalog
- provider unavailable 文案与 resolved provider 都来自 `xworkmate.routing.resolve`

### Gateway Truth

- gateway runtime 可见性、连接状态、mount target discovery 都由 bridge capability / runtime snapshot 驱动
- `xworkmate.gateway.*` 是 gateway runtime 的稳定 app-facing 方法族
- app 不再把 production gateway endpoint、fallback endpoint、local preset 当真源

## Mainline Rules

1. Assistant 所有正常任务都先进入 `GoTaskService.executeTask`。
2. Settings 只管理 bridge connection 参数、account sync 元数据与 gateway/integration affordance。
3. provider catalog、routing resolve、gateway runtime state 都由 bridge 提供。
4. bridge 若暴露额外 capability flag 或协作模式，它们属于合同元数据，不自动抬升为 app shell / module taxonomy。
5. app 不直接调用 `acp-server.svc.plus/*`、`openclaw.svc.plus` 等 upstream 地址。

## Removed From Target

- `TasksPage`、`SkillsPage`、`ModulesPage` 之类独立 surface 叙述
- `local / remote / preset / fallback` 作为 app 一级执行路径心智
- “app 自己维护 provider matrix，再把 bridge 当可选后端”的旧设计
- 通过 alias、compat 分流去保留旧模块入口

## See Also

- [XWorkmate Core Module Inventory](/Users/shenlan/workspaces/cloud-neutral-toolkit/xworkmate-app/docs/architecture/xworkmate-core-module-inventory-2026-04-13.md)
- [Settings Integration Configuration Model](/Users/shenlan/workspaces/cloud-neutral-toolkit/xworkmate-app/docs/architecture/settings-integration-configuration-model.md)
- [ACP Forwarding Topology](/Users/shenlan/workspaces/cloud-neutral-toolkit/xworkmate-bridge/docs/architecture/acp-forwarding-topology.md)
