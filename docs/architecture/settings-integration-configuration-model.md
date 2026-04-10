# Settings Integration Configuration Model

This document records the current logical model behind Settings -> Integrations,
with the provider catalog aligned to the bridge-only design.

## Current Rule

- Settings only manages bridge connection parameters and upstream sync
  definitions.
- The provider picker is not derived from local endpoint presets.
- `xworkmate-bridge` is the only source of truth for the provider catalog.

## Bridge-Only Provider Source Of Truth

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

## Notes

- `externalAcpEndpoints` still matters, but only as bridge sync input.
- Provider visibility, picker contents, and auto-provider resolution all come
  from `acp.capabilities.providers`.
- `openclaw` and other mount-target discovery states are also bridge-owned and
  come from ACP capabilities merged into `ManagedMountTargetState`.
- Persisted thread `providerId` restores the user's previous selection, but it
  does not repopulate the provider catalog.
