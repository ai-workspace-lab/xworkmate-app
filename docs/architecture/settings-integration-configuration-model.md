# Settings Integration Configuration Model

This document records the current logical model behind Settings -> Integrations,
with the provider catalog aligned to the bridge-only design.

## Current Rule

- Settings only manages bridge connection parameters and account sync metadata.
- The provider picker is not derived from local endpoint presets.
- `xworkmate-bridge` is the only source of truth for the provider catalog.

## Bridge-Only Provider Source Of Truth

```mermaid
flowchart TD
  A["Settings UI
  仅管理 Bridge 连接参数
  与账号同步元数据"] --> G["acp.capabilities"]
  G --> H["providerCatalog[]
  singleAgent / multiAgent"]

  H --> I["refreshSingleAgentCapabilitiesRuntimeInternal()"]
  I --> J["bridgeAdvertisedProvidersInternal
  App 内唯一 provider 名单源"]
  I --> K["singleAgentCapabilitiesByProviderInternal
  App 内唯一 provider 可用性源"]

  G --> L["refreshAcpCapabilitiesRuntimeInternal()"]
  L --> M["GatewayAcpCapabilities
  providerCatalog / singleAgent / multiAgent"]
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
  agent / gateway 是否显示
  只看 bridge runtime capabilities"]

  O --> T["visible gateway affordances
  gateway discovery 只看 bridge capabilities"]

  Q --> U["setSingleAgentProvider(providerId)
  仅写入 thread executionBinding.providerId"]

  U --> V["singleAgentProviderForSession()
  恢复线程已选 providerId"]

  V --> W["sendSingleAgentMessageDesktopGoTaskFlowInternal()"]
  W --> X["xworkmate.routing.resolve"]
  X --> Y["bridge 返回 resolvedExecutionTarget /
  resolvedProviderId /
  unavailableCode /
  unavailableMessage"]

  Y --> Z{"unavailable?"}
  Z -->|"no"| AA["executeTask(... resolved routing ...)"]
  Z -->|"yes"| AB["provider unavailable UX
  直接使用 bridge unavailable message"]
```

## Notes

- Production cloud mode does not use app-side provider sync.
- Provider visibility and picker contents come from
  `acp.capabilities.providerCatalog`.
- Auto-provider resolution and unavailable messaging come from
  `xworkmate.routing.resolve`.
- `openclaw` and other mount-target discovery states are also bridge-owned and
  come from ACP capabilities merged into `ManagedMountTargetState`.
- Persisted thread `providerId` restores the user's previous selection, but it
  does not repopulate the provider catalog.
