# Models And Config

## Purpose

这一层覆盖“状态结构”和“配置 contract”，重点在：

- 什么对象被持久化
- 什么对象描述当前连接/执行/provider/catalog
- 哪些 helper 会影响默认值、归一化和展示语义

## `SettingsSnapshot`

- Source: `lib/runtime/runtime_models_settings_snapshot.dart`
- Type: `class`
- Responsibility:
  是当前 app settings 的唯一主快照对象，也是 settings 持久化与恢复的核心 contract。

### Constructor Parameters

| Param Group | Meaning |
| --- | --- |
| app/UI fields | `appLanguage`、`appActive`、`launchAtLogin`、`showDockIcon` |
| workspace/runtime fields | `workspacePath`、`remoteProjectRoot`、`cliPath`、`codeAgentRuntimeMode` |
| execution/provider fields | `defaultModel`、`defaultProvider`、`assistantExecutionTarget`、`assistantPermissionLevel` |
| connection fields | `gatewayProfiles`、`webSessionPersistence` |
| integration fields | `ollamaLocal`、`ollamaCloud`、`vault`、`aiGateway` |
| multi-agent fields | `multiAgent`、`authorizedSkillDirectories` |
| account fields | `accountBaseUrl`、`accountUsername`、`accountWorkspace`、`accountWorkspaceFollowed` |
| desktop/server fields | `acpBridgeServerModeConfig`、`linuxDesktop` |

### Key Returns

| API | Returns | Meaning |
| --- | --- | --- |
| `SettingsSnapshot.defaults()` | `SettingsSnapshot` | 当前 schema 的默认配置 |
| `copyWith(...)` | `SettingsSnapshot` | 产生归一化后的新快照 |
| `toJson()` | `Map<String, dynamic>` | 序列化 |
| `fromJson(Map<String, dynamic>)` | `SettingsSnapshot` | 反序列化并校验 schema |

### Notes

- `schemaVersion` 当前固定为 `2`
- 这里是 settings 持久化 contract，不应该承载临时 UI-only 状态

## `GatewayConnectionProfile`

- Source: `lib/runtime/runtime_models_configs.dart`
- Type: `class`
- Responsibility:
  描述单个 gateway 连接槽位，支持 setup code 与手工 host/port/tls 两种配置形态。

### Constructor Parameters

| Param | Type | Required | Meaning |
| --- | --- | --- | --- |
| `mode` | `RuntimeConnectionMode` | Yes | unconfigured / remote |
| `useSetupCode` | `bool` | Yes | 是否使用 setup code |
| `setupCode` | `String` | Yes | setup code 内容 |
| `host` | `String` | Yes | 远端 host |
| `port` | `int` | Yes | 端口 |
| `tls` | `bool` | Yes | 是否 TLS |
| `tokenRef` | `String` | Yes | token secret ref |
| `passwordRef` | `String` | Yes | password secret ref |
| `selectedAgentId` | `String` | Yes | 当前 profile 默认 agent |

### Key Returns

| API | Returns | Meaning |
| --- | --- | --- |
| `defaults()` / `defaultsGateway()` | `GatewayConnectionProfile` | 默认 gateway profile |
| `emptySlot({required int index})` | `GatewayConnectionProfile` | 非主 profile 的空槽位 |
| `copyWith(...)` | `GatewayConnectionProfile` | 自动做 endpoint 归一化 |
| `toJson()` / `fromJson(...)` | contract mapping | 序列化/恢复 |

## `normalizeGatewayProfiles`

- Source: `lib/runtime/runtime_models_configs.dart`
- Type: `top-level function`
- Responsibility:
  对 gateway profile 列表做长度补齐、主槽位 remote 判定、loopback 剔除、token/password ref 修补。

### Parameters and Returns

| Parameters | Returns | Meaning |
| --- | --- | --- |
| `{Iterable<GatewayConnectionProfile>? profiles}` | `List<GatewayConnectionProfile>` | 固定长度、可持久化的 profile 列表 |

## `RuntimeConnectionMode` / `RuntimeConnectionStatus`

- Source: `lib/runtime/runtime_models_connection.dart`
- Type: `enum`
- Responsibility:
  区分“配置形态”和“实时连接状态”。

### Returns

| Enum | Key Returns |
| --- | --- |
| `RuntimeConnectionMode` | `label`, `fromJsonValue` |
| `RuntimeConnectionStatus` | `label` |

## `AssistantExecutionTarget`

- Source: `lib/runtime/runtime_models_connection.dart`
- Type: `enum`
- Responsibility:
  表示当前 thread 最终是落到 `agent` 还是 `gateway`。

### Returns

| Getter / API | Returns | Meaning |
| --- | --- | --- |
| `label` / `compactLabel` | `String` | 展示标签 |
| `promptValue` | `String` | 发给 routing / prompt 的规范值 |
| `isAgent` / `isGateway` | `bool` | 类型判断 |
| `fromJsonValue` | `AssistantExecutionTarget` | 持久化恢复 |

## `SingleAgentProvider`

- Source: `lib/runtime/runtime_models_connection.dart`
- Type: `class`
- Responsibility:
  是 app 侧统一 provider 模型，同时承载 agent provider 与 gateway provider。

### Constructor Parameters

| Param | Type | Required | Meaning |
| --- | --- | --- | --- |
| `providerId` | `String` | Yes | 归一化 provider ID |
| `label` | `String` | Yes | 展示名 |
| `badge` | `String` | Yes | 短徽标 |
| `logoEmoji` | `String` | No | 可选 emoji |
| `supportedTargets` | `List<AssistantExecutionTarget>` | No | 支持的执行目标 |
| `enabled` | `bool` | No | 是否可用 |
| `unavailableReason` | `String` | No | 不可用说明 |
| `source` | `SingleAgentProviderSource` | No | 来源 |

### Key Returns

| API / Getter | Returns | Meaning |
| --- | --- | --- |
| `isUnspecified` | `bool` | 是否空 provider |
| `copyWith(...)` | `SingleAgentProvider` | 生成归一化副本 |
| `codex` / `opencode` / `claude` / `gemini` / `openclaw` | constants | 预置 provider 常量 |

## `GatewayConnectionSnapshot`

- Source: `lib/runtime/runtime_models_runtime_payloads.dart`
- Type: `class`
- Responsibility:
  描述 `GatewayRuntime` 当前连接快照，包括 status、auth mode、health/status 原始负载、错误码和 main session key。

### Constructor Parameters

| Param Group | Meaning |
| --- | --- |
| connectivity | `status`, `mode`, `statusText`, `remoteAddress`, `lastConnectedAtMs` |
| identity/auth | `deviceId`, `authRole`, `authScopes`, `connectAuthMode`, `connectAuthFields`, `connectAuthSources` |
| error | `lastError`, `lastErrorCode`, `lastErrorDetailCode` |
| payloads | `healthPayload`, `statusPayload` |

### Key Returns

| API | Returns | Meaning |
| --- | --- | --- |
| `initial(...)` | `GatewayConnectionSnapshot` | 初始离线快照 |
| `copyWith(...)` | `GatewayConnectionSnapshot` | 生成新快照 |
| `normalizedForConnectedState()` | `GatewayConnectionSnapshot` | connected 时清理历史错误 |
| `gatewayTokenMissing` | `bool` | 识别 AUTH_TOKEN_MISSING 场景 |
| `connectAuthSummary` | `String` | 汇总当前鉴权来源 |

## `AiGatewayProfile`

- Source: `lib/runtime/runtime_models_configs.dart`
- Type: `class`
- Responsibility:
  描述 AI gateway 地址、模型选择、密钥 ref、catalog 及联通性状态。

### Key Returns

| API | Returns | Meaning |
| --- | --- | --- |
| `defaults()` | `AiGatewayProfile` | 默认 profile |
| `copyWith(...)` | `AiGatewayProfile` | 更新 profile |
| `toJson()` / `fromJson(...)` | contract mapping | 序列化 / 恢复 |

## `MultiAgentConfig`

- Source: `lib/runtime/runtime_models_multi_agent.dart`
- Type: `class`
- Responsibility:
  描述 native / ARIS 多 agent 协作的总配置，包括角色 worker、迭代次数、超时、AI gateway 注入策略、managed skills/MCP/mount targets。

### Constructor Parameters

| Param Group | Meaning |
| --- | --- |
| enable/framework | `enabled`, `autoSync`, `framework`, `arisEnabled`, `arisMode`, `arisBundleVersion`, `arisCompatStatus` |
| worker roles | `architect`, `engineer`, `tester` |
| execution policy | `ollamaEndpoint`, `maxIterations`, `minAcceptableScore`, `timeoutSeconds`, `aiGatewayInjectionPolicy` |
| managed assets | `managedSkills`, `managedMcpServers`, `mountTargets` |

### Key Returns

| API / Getter | Returns | Meaning |
| --- | --- | --- |
| `defaults()` | `MultiAgentConfig` | 默认协作配置 |
| `architectEnabled` / `architectTool` / `architectModel` | primitive | Architect 快捷访问 |
| `engineerTool` / `engineerModel` | primitive | Engineer 快捷访问 |
| `testerTool` / `testerModel` | primitive | Tester 快捷访问 |
| `usesAris` | `bool` | 当前是否落到 ARIS |

## `AgentWorkerConfig`

- Source: `lib/runtime/runtime_models_multi_agent.dart`
- Type: `class`
- Responsibility:
  描述单个角色 worker 的 CLI、模型与重试策略。

### Constructor Parameters

| Param | Type | Required | Default | Meaning |
| --- | --- | --- | --- | --- |
| `role` | `MultiAgentRole` | Yes | none | 角色 |
| `cliTool` | `String` | Yes | none | `claude/codex/opencode/...` |
| `model` | `String` | Yes | none | 对应模型 |
| `enabled` | `bool` | Yes | none | 是否启用 |
| `maxRetries` | `int` | No | `2` | 最大重试次数 |

## `AppTheme` / `AppPalette`

- Source: `lib/theme/app_theme.dart`, `lib/theme/app_palette.dart`
- Type: `class`
- Responsibility:
  虽然属于 UI 层，但它们是工程上可复用的主题入口，因此保留在公开接口层。

### Notes

- `AppTheme` 负责 spacing/radius/typography/sizes 与 `ThemeData` 组合
- `AppPalette` 是 `ThemeExtension`，为业务页面和 shell 提供调色板入口
