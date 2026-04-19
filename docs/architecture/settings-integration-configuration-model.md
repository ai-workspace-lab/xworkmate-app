# Settings Integration Configuration Model

Last Updated: 2026-04-19

本文件记录当前 `Settings -> Integrations` 在主链中的职责边界，以及
`acpBridgeServerModeConfig` 的有效配置仲裁规则。

## Current Rule

- Settings 只管理 Bridge 连接参数、account sync 元数据和本地编辑态
- `AcpBridgeServerModeConfig.effective` 是运行时实际生效配置
- `selfHosted` 优先级高于 `cloudSynced`
- `cloudSynced` 只在 manual Bridge 未配置时作为有效回退来源
- app 不从本地 endpoint preset、旧 module 配置、历史 fallback 恢复 provider catalog
- `xworkmate-bridge` 仍然是 provider catalog、gateway capability、routing resolve 的唯一真源
- `BRIDGE_SERVER_URL` 只属于 `AccountSyncState` 元数据
- `BRIDGE_AUTH_TOKEN` 只进入 secure storage / managed secret

## Canonical State Model

For the detailed state diagram and ownership rules, see:

- [Account Sync, Settings, and Bridge State Model](/Users/shenlan/workspaces/cloud-neutral-toolkit/xworkmate-app/docs/architecture/account-sync-settings-bridge-state-model.md)

## Bridge-Owned Source Of Truth

```mermaid
flowchart TD
  subgraph SETTINGS["Settings surface"]
    A["SettingsPage / SettingsAccountPanel"]
    B["bridge connection params<br/>account sync metadata<br/>secure refs"]
    A --> B
  end

  subgraph BRIDGE["Bridge contract"]
    C["acp.capabilities"]
    D["xworkmate.routing.resolve"]
    E["xworkmate.gateway.*"]
    B --> C
  end

  subgraph APPSTATE["App-side derived state"]
    F["capability refresh hydration"]
    G["bridgeAgentProviderCatalogInternal<br/>bridgeGatewayProviderCatalogInternal<br/>bridgeAvailableExecutionTargetsInternal"]
    H["GatewayAcpCapabilities"]
    I["gateway capability -> mount target merge"]
    J["ManagedMountTargetState"]
    C --> F --> G
    C --> H --> I --> J
  end

  subgraph UI["Visible affordances"]
    M["agent / gateway target switch"]
    N["task dialog provider menu"]
    O["settings gateway connection affordances"]
    G --> M
    G --> N
    J --> O
  end

  subgraph EXEC["Execution"]
    P["providerCatalogForExecutionTarget()"]
    Q["resolveProviderForExecutionTarget()"]
    R["setAssistantProvider()"]
    S["assistantProviderForSession()"]
    T["GoTaskService.executeTask(...)"]
    U["resolved provider / unavailable UX"]
    N --> P --> Q --> R --> S --> T
    T --> D --> U
    O --> E
  end
```

## What Settings Owns

- bridge host / transport / auth input
- account-linked bridge configuration metadata
- `acpBridgeServerModeConfig.cloudSynced`
- `acpBridgeServerModeConfig.selfHosted`
- `acpBridgeServerModeConfig.effective`
- secure secret references
- gateway connection test / connect / disconnect affordance

## What Settings Does Not Own

- 独立 provider catalog
- 独立 module matrix
- app-side gateway preset backfill
- 旧 `ai_gateway` / `secrets` / `account` 页面壳

## Notes

- `AcpBridgeServerModeConfig` 的实际仲裁顺序是 `selfHosted -> cloudSynced -> default`
- `selfHosted.isConfigured == true` 时，`effective.source == 'bridge'`
- `selfHosted` 未配置且 `accountSyncState` 提供了可用云端桥接信息时，`effective.source == 'cloud'`
- 两者都不可用时，`effective.source == 'default'`
- 当前任务对话框 provider 选择主链固定为 `providerCatalogForExecutionTarget() -> resolveProviderForExecutionTarget() -> setAssistantProvider()`
- `agent` catalog 只对应 bridge 广告的 ACP server bridges
- `gateway` catalog 只对应 bridge 返回的 gateway provider 列表；当前为 `openclaw`，未来可扩展 `hermes` 等项
- provider picker 的真源只来自 bridge 返回的 target-scoped catalog；不会因为线程里保存过 `providerId` 就被 app 反向重建
- gateway runtime 可见性来自 bridge capability snapshot 与 `xworkmate.gateway.*` 返回，不来自旧设置页枚举
- bridge 若返回额外 capability flag，这些 flag 只属于合同元数据，不会自动生成新的 settings tab 或 module page
- bridge 若未返回 catalog，provider 菜单为空或禁用；app 不伪造 `codex / opencode / gemini / openclaw`
- production provider / gateway 选择继续由 bridge 拥有，app 只保留消费与展示

## Effective Config Mermaid

```mermaid
stateDiagram-v2
    [*] --> EvaluateEffective

    EvaluateEffective --> BridgeEffective: selfHosted.isConfigured == true
    EvaluateEffective --> CloudEffective: selfHosted 未配置 且 cloudSynced 可用
    EvaluateEffective --> DefaultEffective: 两者都不可用

    BridgeEffective --> CloudEffective: 关闭 manual Bridge
    CloudEffective --> BridgeEffective: manual Bridge 配置生效
    CloudEffective --> DefaultEffective: cloud sync 失效
    DefaultEffective --> CloudEffective: cloud sync 恢复

    note right of BridgeEffective
        source = bridge
        effective.endpoint = selfHosted.serverUrl
    end note

    note right of CloudEffective
        source = cloud
        effective.endpoint = accountSyncState.syncedDefaults.bridgeServerUrl
    end note

    note right of DefaultEffective
        source = default
        effective.endpoint = kManagedBridgeServerUrl
    end note
```

## See Also

- [Task Dialog Provider Selection Mainline](/Users/shenlan/workspaces/cloud-neutral-toolkit/xworkmate-app/docs/architecture/task-dialog-provider-selection-mainline.md)
