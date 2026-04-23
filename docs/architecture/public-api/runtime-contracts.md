# Runtime Contracts

## Module Purpose

`lib/runtime` 是当前仓库的最大公开接口面。这里承接的不是“视觉状态”，而是：

- bridge ACP / gateway runtime 合同
- task request / routing request / provider catalog
- settings 与 secret 持久化访问
- gateway session / agent / chat 控制器
- desktop 平台能力、skill 目录授权、多 agent mount
- Codex CLI 与 config bridge

## `GatewayAcpException`

- Source: `lib/runtime/gateway_acp_client.dart`
- Type: `class`
- Responsibility:
  表示 ACP JSON-RPC 失败、能力缺失或协议错误。

### Constructor Parameters

| Param | Type | Required | Default | Meaning |
| --- | --- | --- | --- | --- |
| `message` | `String` | Yes | none | 错误摘要 |
| `code` | `String?` | No | `null` | 协议级错误码 |
| `details` | `Object?` | No | `null` | 原始错误负载 |

### Returns

| API | Returns | Meaning |
| --- | --- | --- |
| `toString()` | `String` | 输出 `code: message` 或纯 message |

## `GatewayAcpCapabilities`

- Source: `lib/runtime/gateway_acp_client.dart`
- Type: `class`
- Responsibility:
  保存 `acp.capabilities` 的解析结果，是 app 侧 single-agent / multi-agent / execution-target / provider catalog 的只读快照。

### Constructor Parameters

| Param | Type | Required | Meaning |
| --- | --- | --- | --- |
| `singleAgent` | `bool` | Yes | 是否支持单 agent |
| `multiAgent` | `bool` | Yes | 是否支持多 agent |
| `availableExecutionTargets` | `List<AssistantExecutionTarget>` | Yes | 当前 bridge 允许的执行目标 |
| `providerCatalog` | `List<SingleAgentProvider>` | Yes | agent 侧 provider catalog |
| `gatewayProviderCatalog` | `List<SingleAgentProvider>` | Yes | gateway 侧 provider catalog |
| `raw` | `Map<String, dynamic>` | Yes | 原始 capability 负载 |
| `diagnostics` | `Map<String, dynamic>` | No | 可选诊断信息 |

### Returns

| API | Returns | Meaning |
| --- | --- | --- |
| `GatewayAcpCapabilities.empty()` | `GatewayAcpCapabilities` | 空 capability 占位 |

## `GatewayAcpMultiAgentRequest`

- Source: `lib/runtime/gateway_acp_client.dart`
- Type: `class`
- Responsibility:
  描述一次 multi-agent thread/start / turn/start 请求。

### Constructor Parameters

| Param | Type | Required | Meaning |
| --- | --- | --- | --- |
| `sessionId` | `String` | Yes | 协作会话 ID |
| `threadId` | `String` | Yes | thread ID |
| `prompt` | `String` | Yes | 主任务提示词 |
| `workingDirectory` | `String` | Yes | 工作目录 |
| `attachments` | `List<CollaborationAttachment>` | Yes | 本地文件附件 |
| `selectedSkills` | `List<String>` | Yes | 显式选中的技能键 |
| `resumeSession` | `bool` | Yes | `false` 时发 `thread/start`，`true` 时发 `turn/start` |

## `GatewayAcpClient`

- Source: `lib/runtime/gateway_acp_client.dart`
- Type: `class`
- Responsibility:
  XWorkmate 对 ACP JSON-RPC 的 app-side client，负责 endpoint 解析、auth header 注入、capability 拉取、多 agent 事件流转发。

### Constructor Parameters

| Param | Type | Required | Meaning |
| --- | --- | --- | --- |
| `endpointResolver` | `Uri? Function()` | Yes | 当前 ACP endpoint 解析器 |
| `authorizationResolver` | `Future<String?> Function(Uri endpoint)?` | No | endpoint 对应的授权头解析器 |

### Key Methods

| Method | Parameters | Returns | Meaning |
| --- | --- | --- | --- |
| `loadCapabilities` | `{bool forceRefresh=false, Uri? endpointOverride, String authorizationOverride=''}` | `Future<GatewayAcpCapabilities>` | 拉取并缓存 15 秒 capability 快照 |
| `runMultiAgent` | `GatewayAcpMultiAgentRequest request` | `Stream<MultiAgentRunEvent>` | 打开 ACP multi-agent 事件流 |

### Main Call Chain

- `AppController.refreshAcpCapabilitiesRuntimeInternal` -> `loadCapabilities`
- `GoRuntimeDispatchDesktopClient` / multi-agent flows -> `GatewayAcpClient`
- `GatewayAcpClient` -> ACP JSON-RPC -> bridge

### Side Effects

- 网络请求
- 本地 capability 缓存
- 将 ACP 通知转换成 `MultiAgentRunEvent`

## `ExternalCodeAgentAcpCapabilities`

- Source: `lib/runtime/go_task_service_client.dart`
- Type: `class`
- Responsibility:
  表示 Go task service 视角下的外部 ACP 能力镜像，主要用于任务路由与执行目标可见性判断。

## `ExternalCodeAgentAcpRoutingResolution`

- Source: `lib/runtime/go_task_service_client.dart`
- Type: `class`
- Responsibility:
  包装 bridge 返回的 routing resolution，给调用方提供 `resolvedExecutionTarget`、`resolvedProviderId`、`resolvedSkills`、`unavailable*` 等只读 getter。

### Returns

| Getter | Returns | Meaning |
| --- | --- | --- |
| `resolvedExecutionTarget` | `String` | 归一化后的执行目标 |
| `resolvedProviderId` | `String` | 解析后的 provider |
| `resolvedGatewayProviderId` | `String` | 解析后的 gateway provider |
| `resolvedModel` | `String` | 解析后的模型 |
| `resolvedSkills` | `List<String>` | 解析后的技能列表 |
| `unavailable` | `bool` | 路由是否不可用 |
| `unavailableCode` / `unavailableMessage` | `String` | 不可用原因 |

## `ExternalCodeAgentAcpRoutingConfig`

- Source: `lib/runtime/go_task_service_client.dart`
- Type: `class`
- Responsibility:
  描述一次任务执行时 app 侧给 bridge 的 routing 约束，包括 auto/explicit 模式、执行目标、provider、模型、技能、自动安装许可。

### Constructor Parameters

| Param | Type | Required | Meaning |
| --- | --- | --- | --- |
| `mode` | `ExternalCodeAgentAcpRoutingMode` | Yes | `auto` or `explicit` |
| `preferredGatewayTarget` | `String` | Yes | 自动模式下偏好的 gateway 目标 |
| `explicitExecutionTarget` | `String` | Yes | 显式执行目标 |
| `explicitProviderId` | `String` | Yes | 显式 provider |
| `explicitModel` | `String` | Yes | 显式模型 |
| `explicitSkills` | `List<String>` | Yes | 显式技能列表 |
| `allowSkillInstall` | `bool` | Yes | 是否允许安装缺失技能 |
| `availableSkills` | `List<ExternalCodeAgentAcpAvailableSkill>` | Yes | 当前可见技能清单 |
| `installApproval` | `ExternalCodeAgentAcpSkillInstallApproval?` | No | 安装批准信息 |

### Returns

| API | Returns | Meaning |
| --- | --- | --- |
| `isAuto` | `bool` | 当前是否自动路由 |
| `toJson()` | `Map<String, dynamic>` | 生成 bridge 请求负载 |

## `GoTaskServiceRequest`

- Source: `lib/runtime/go_task_service_client.dart`
- Type: `class`
- Responsibility:
  是 desktop task execution 的统一请求模型。无论最终落到 external ACP single、external ACP multi 还是 gateway mode，都由它统一描述。

### Constructor Parameters

| Param | Type | Required | Meaning |
| --- | --- | --- | --- |
| `sessionId` / `threadId` | `String` | Yes | 会话与线程标识 |
| `target` | `AssistantExecutionTarget` | Yes | 目标执行面 |
| `prompt` | `String` | Yes | 用户任务文本 |
| `workingDirectory` | `String` | Yes | 本地工作目录 |
| `model` / `thinking` | `String` | Yes | 模型与 thinking 档位 |
| `selectedSkills` | `List<String>` | Yes | 技能键 |
| `inlineAttachments` | `List<GatewayChatAttachmentPayload>` | Yes | base64 内联附件 |
| `localAttachments` | `List<CollaborationAttachment>` | Yes | 本地文件附件 |
| `agentId` | `String` | Yes | 目标 agent ID |
| `metadata` | `Map<String, dynamic>` | Yes | 额外元数据 |
| `routing` | `ExternalCodeAgentAcpRoutingConfig?` | No | 可选显式 routing |
| `provider` | `SingleAgentProvider` | No | 当前 provider |
| `remoteWorkingDirectoryHint` | `String` | No | 远端工作目录 hint |
| `resumeSession` | `bool` | No | 是否续跑 |
| `collaborationMode` | `GoTaskServiceCollaborationMode` | No | standard / multiAgent |
| `multiAgent` | `bool` | No | 是否强制多 agent |

### Returns

| Getter / Method | Returns | Meaning |
| --- | --- | --- |
| `isMultiAgentRequest` | `bool` | 是否走多 agent route |
| `route` | `GoTaskServiceRoute` | 计算出的实际 route |
| `acpMode` | `String` | ACP session mode |
| `routingExecutionTarget` | `String` | 发送给 routing 的目标值 |
| `effectiveRouting` | `ExternalCodeAgentAcpRoutingConfig` | 若未传入则自动合成 |
| `toExternalAcpParams()` | `Map<String, dynamic>` | 生成 external ACP 请求参数 |

### Main Call Chain

- `AppControllerDesktopWorkspaceExecution` -> `GoTaskServiceRequest`
- `DesktopGoTaskService.execute*` -> `toExternalAcpParams()`
- bridge 根据 routing 再决定 gateway / agent provider 落点

## `SettingsController`

- Source: `lib/runtime/runtime_controllers_settings.dart`
- Type: `class`
- Responsibility:
  统一管理 `SettingsSnapshot`、secret refs、audit trail、account state、settings 文件监控和测试连接入口。

### Constructor Parameters

| Param | Type | Required | Meaning |
| --- | --- | --- | --- |
| `storeInternal` | `SecureConfigStore` | Yes | 底层持久化与 secret store |
| `accountClientFactory` | `AccountRuntimeClient Function(String baseUrl)?` | No | 自定义 account client 构造器 |

### Key Methods

| Method | Parameters | Returns | Meaning |
| --- | --- | --- | --- |
| `initialize` | none | `Future<void>` | 读取 snapshot、启动 watcher、加载派生状态 |
| `refreshDerivedState` | none | `Future<void>` | 仅刷新派生状态 |
| `saveSnapshot` | `SettingsSnapshot snapshot` | `Future<void>` | 落盘 settings |
| `saveGatewaySecrets` | `{int? profileIndex, required String token, required String password}` | `Future<void>` | 保存 gateway secret |
| `loadGatewayToken` / `loadGatewayPassword` | `{int? profileIndex}` | `Future<String>` | 读取 gateway 凭据 |
| `testOllamaConnection` | `{required bool cloud}` | `Future<String>` | 测试 Ollama 连接 |
| `testVaultConnectionDraft` | `VaultConfig profile, {String tokenOverride=''}` | `Future<String>` | 使用草稿配置测试 vault |

### Side Effects

- 文件系统 watcher
- secure storage 与 settings JSON 文件
- account session / sync / MFA

## Gateway Runtime Controllers

### `GatewayAgentsController`

- Source: `lib/runtime/runtime_controllers_gateway.dart`
- Responsibility:
  管理 gateway agent 列表、当前选中 agent 与 refresh 状态。

### `GatewaySessionsController`

- Source: `lib/runtime/runtime_controllers_gateway.dart`
- Responsibility:
  管理 session summary 列表、当前 session key、agent-base session 推导。

### `GatewayChatController`

- Source: `lib/runtime/runtime_controllers_gateway.dart`
- Responsibility:
  管理当前会话的消息历史、streaming 文本、pending run、chat/agent 事件消费。

### Common API Shape

| Controller | Key Parameters | Returns |
| --- | --- | --- |
| `refresh()` | none | `Future<void>` |
| `switchSession(String sessionKey)` | `String` | `Future<void>` |
| `loadSession(String sessionKey)` | `String` | `Future<void>` |
| `handleEvent(GatewayPushEvent event)` | `GatewayPushEvent` | `void` |

## `GatewayRuntime`

- Source: `lib/runtime/gateway_runtime_core.dart`
- Type: `class`
- Responsibility:
  对 websocket gateway 的连接、鉴权、请求、事件订阅、session client 更新、device identity 和日志做统一管理。

### Constructor Parameters

| Param | Type | Required | Meaning |
| --- | --- | --- | --- |
| `store` | `SecureConfigStore` | Yes | settings/secret/device token 存储 |
| `identityStore` | `DeviceIdentityStore` | Yes | 设备身份持久化 |
| `sessionClient` | `GatewayRuntimeSessionClient?` | No | 直接 session client |
| `runtimeId` | `String` | No | runtime 实例 ID，空时自动生成 |

### Key Methods

| Method | Parameters | Returns | Meaning |
| --- | --- | --- | --- |
| `initialize` | none | `Future<void>` | 初始化 package/device/session updates |
| `connectProfile` | `GatewayConnectionProfile profile, {int? profileIndex, String authTokenOverride='', String authPasswordOverride=''}` | `Future<void>` | 按 profile 建立连接 |
| `request` | RPC params | `Future<Map<String, dynamic>>` | 发 websocket RPC |
| `listAgents` | none | `Future<List<GatewayAgentSummary>>` | 取 agent 清单 |
| `listSessions` | `{String? agentId, int limit=24}` | `Future<List<GatewaySessionSummary>>` | 取 session 清单 |
| `loadHistory` | `String sessionKey, {int limit=120}` | `Future<List<GatewayChatMessage>>` | 取会话历史 |
| `sendChat` | named args | `Future<String>` | 发消息并返回 runId |
| `abortChat` | `{required String sessionKey, required String runId}` | `Future<void>` | 终止 run |
| `stop` | none | `Future<void>` | 断连并清理资源 |

### Main Call Chain

- `AppController` / `Gateway*Controller` -> `GatewayRuntime`
- `GatewayRuntime` -> websocket RPC / `GatewayRuntimeSessionClient`
- 返回 `GatewayPushEvent` 与 snapshot 更新给上层 controller

### Side Effects

- 网络 websocket
- device token / shared token / password 鉴权
- runtime logs 与 reconnect timer

## `GatewayRuntimeSessionClient`

- Source: `lib/runtime/gateway_runtime_session_client.dart`
- Type: `abstract class`
- Responsibility:
  描述 session connect/update 的外部实现边界，允许 runtime 接入不同 session 数据源。

### Key Types

| Type | Role |
| --- | --- |
| `GatewayRuntimeSessionConnectRequest` | 连接 session 的入参 |
| `GatewayRuntimeSessionConnectResult` | 连接结果 |
| `GatewayRuntimeSessionUpdate` | 增量更新负载 |

## `RuntimeBootstrapConfig`

- Source: `lib/runtime/runtime_bootstrap.dart`
- Type: `class`
- Responsibility:
  从 repo / `.env` / OpenClaw 邻接路径中解析启动期默认值，并把“仅用于预填”的 bootstrap 值合并到 `SettingsSnapshot`。

### Key Methods

| Method | Parameters | Returns | Meaning |
| --- | --- | --- | --- |
| `load` | `{String? workspacePathHint, String? cliPathHint}` | `Future<RuntimeBootstrapConfig>` | 扫描 workspace/OpenClaw/.env 得到 bootstrap 配置 |
| `mergeIntoSettings` | `SettingsSnapshot snapshot` | `SettingsSnapshot` | 只在默认/瞬时路径场景下注入预填值 |
| `preferredGatewayFor` | `RuntimeConnectionMode mode` | `GatewayBootstrapTarget?` | 给连接模式选择 bootstrap gateway |

### Notes

- 这里遵循仓库安全规则：`.env` 只做预填，不做自动连接真源

## `GatewayBootstrapTarget`

- Source: `lib/runtime/runtime_bootstrap.dart`
- Type: `class`
- Responsibility:
  描述 bootstrap 阶段解析出来的远程 gateway 目标。

### Constructor Parameters

| Param | Type | Required | Meaning |
| --- | --- | --- | --- |
| `mode` | `RuntimeConnectionMode` | Yes | 当前只用于 remote |
| `url` | `String` | Yes | 原始 URL |
| `host` | `String` | Yes | 解析后的 host |
| `port` | `int` | Yes | 解析后的端口 |
| `tls` | `bool` | Yes | 是否 TLS |
| `token` | `String` | Yes | 可选 bootstrap token |

## `AgentRegistry`

- Source: `lib/runtime/agent_registry.dart`
- Type: `class`
- Responsibility:
  聚合 gateway 暴露的 agent capability / registration / response，给 app 侧 provider 与 bridge 节点注册使用。

## `SkillDirectoryAccessService`

- Source: `lib/runtime/skill_directory_access.dart`
- Type: `abstract class`
- Responsibility:
  抽象 skill 目录授权入口。平台实现包括文件选择器和 macOS bookmark 能力。

### Main Implementations

| Type | Meaning |
| --- | --- |
| `UnsupportedSkillDirectoryAccessService` | 平台不支持时的空实现 |
| `FileSelectorSkillDirectoryAccessService` | 通用文件选择器实现 |
| `MacOsSkillDirectoryAccessService` | macOS bookmark/持久授权实现 |

## `DesktopPlatformService`

- Source: `lib/runtime/desktop_platform_service.dart`
- Type: `abstract class`
- Responsibility:
  抽象 tunnel/proxy/VPN 模式、系统平台集成刷新与切换能力。

### Main Implementations

| Type | Meaning |
| --- | --- |
| `UnsupportedDesktopPlatformService` | 无平台支持时的降级实现 |
| `MethodChannelDesktopPlatformService` | 通过 method channel 驱动平台能力 |

## `CodexRuntime`

- Source: `lib/runtime/codex_runtime.dart`
- Type: `class`
- Responsibility:
  管理本地 Codex CLI stdio 进程、线程/turn RPC、事件流和账户查询。

### Key Methods

| Method | Parameters | Returns | Meaning |
| --- | --- | --- | --- |
| `findCodexBinary` | none | `Future<String?>` | 解析 codex 二进制路径 |
| `startStdio` | named args | `Future<void>` | 以 stdio 模式启动 Codex CLI |
| `request` | RPC request params | `Future<Map<String, dynamic>>` | 发 Codex RPC 请求 |
| `startThread` | `{required String cwd, bool ephemeral=false}` | `Future<CodexThread>` | 新建 thread |
| `resumeThread` | `{required String threadId}` | `Future<CodexThread>` | 恢复 thread |
| `sendMessage` | named args | `Stream<CodexTurnEvent>` | 对 thread 发消息并返回事件流 |
| `interrupt` | `{required String threadId}` | `Future<void>` | 中断运行 |
| `getAccount` | none | `Future<CodexAccount>` | 拉账户信息 |
| `listModels` | named args | `Future<List<Map<String, dynamic>>>` | 列模型 |
| `listSkills` | `{required String cwd}` | `Future<List<Map<String, dynamic>>>` | 列技能 |
| `stop` | none | `Future<void>` | 停止进程与清理 |

### Key Companion Types

| Type | Role |
| --- | --- |
| `CodexThread` | thread 元数据 |
| `CodexTurn` | turn 元数据 |
| `CodexAccount` / `CodexRateLimit` | 账户与限额 |
| `CodexUserInput` / `CodexAttachment` | 入参模型 |
| `CodexRpcError` | RPC 错误 |
| `CodexLaunchConfiguration` | 嵌入式启动配置 |

## `CodexConfigBridge`

- Source: `lib/runtime/codex_config_bridge.dart`
- Type: `class`
- Responsibility:
  负责把 app settings 与 Codex 配置文件 / MCP server 配置桥接起来，是 `CodexRuntime` 之外的“配置写入侧”。
