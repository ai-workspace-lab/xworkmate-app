# App Orchestration

## Module Purpose

`lib/app` 负责把 `feature_flags -> shell/registry -> AppController -> runtime/controller` 这条主链收口到统一桌面/移动编排层。这里的公开接口重点不在“UI 细节”，而在：

- 顶层状态与依赖装配
- 页面 destination 与 registry
- 设置、线程、provider、执行目标的落盘与切换
- 运行时能力刷新与线程上下文重算

## Key Files

| File | Role |
| --- | --- |
| `lib/app/app_controller_desktop_core.dart` | `AppController` 主对象、依赖装配与状态总线 |
| `lib/app/app_controller_desktop_navigation.dart` | 页面切换、settings/detail 导航、语言/主题切换 |
| `lib/app/app_controller_desktop_settings.dart` | settings draft、保存、落盘与本地状态清理 |
| `lib/app/app_controller_desktop_settings_runtime.dart` | settings 与 runtime 之间的副作用桥接 |
| `lib/app/app_controller_desktop_thread_sessions.dart` | 会话/线程、artifact、多 agent 协作入口 |
| `lib/app/app_controller_desktop_workspace_execution.dart` | 执行目标、provider、thread context 主链 |
| `lib/app/app_controller_desktop_runtime_coordination_impl.dart` | runtime 能力刷新与任务重算函数 |
| `lib/app/workspace_page_registry.dart` | destination 到 page builder 的唯一映射 |
| `lib/app/app_shell_desktop.dart` | 桌面/移动入口壳层 |

## `AppController`

- Source: `lib/app/app_controller_desktop_core.dart`
- Type: `class`
- Responsibility:
  统一装配 `SecureConfigStore`、`RuntimeCoordinator`、`GatewayRuntime`、`CodexRuntime`、`SettingsController`、各类 gateway controller、task thread 状态、UI feature manifest。

### Constructor Parameters

| Param | Type | Required | Default | Meaning |
| --- | --- | --- | --- | --- |
| `store` | `SecureConfigStore?` | No | `SecureConfigStore()` | 设置与 secret 持久化入口 |
| `runtimeCoordinator` | `RuntimeCoordinator?` | No | 内建 coordinator | 收口 gateway/codex/config bridge |
| `desktopPlatformService` | `DesktopPlatformService?` | No | `createDesktopPlatformService()` | 平台 VPN/集成能力桥 |
| `uiFeatureManifest` | `UiFeatureManifest?` | No | repo manifest | 顶层 surface 能力声明源 |
| `initialBridgeProviderCatalog` | `List<SingleAgentProvider>?` | No | empty | 初始单 agent provider catalog |
| `initialGatewayProviderCatalog` | `List<SingleAgentProvider>?` | No | empty | 初始 gateway provider catalog |
| `initialAvailableExecutionTargets` | `List<AssistantExecutionTarget>?` | No | empty | 初始可见执行目标 |
| `skillDirectoryAccessService` | `SkillDirectoryAccessService?` | No | platform factory | 技能目录授权能力 |
| `accountClientFactory` | `AccountRuntimeClient Function(String)?` | No | default impl | account runtime client 构造 |
| `environmentOverride` | `Map<String, String>?` | No | `null` | 测试/运行时环境覆盖 |
| `singleAgentSharedSkillScanRootOverrides` | `List<String>?` | No | `null` | 共享 skill 扫描根覆写 |
| `arisBundleRepository` | `ArisBundleRepository?` | No | default impl | ARIS bundle 发现仓库 |
| `goTaskServiceClient` | `GoTaskServiceClient?` | No | `DesktopGoTaskService` | 外部 ACP / gateway 任务入口 |
| `multiAgentMountManager` | `MultiAgentMountManager?` | No | default impl | 多 agent mount 管理器 |

### Returns

| Constructor / API | Returns | Meaning |
| --- | --- | --- |
| `AppController(...)` | `AppController` | 初始化后的应用总控制器 |

### Main Call Chain

- `XWorkmateApp` / `AppShell` 持有 `AppController`
- `AppController` 组合 `SettingsController`、`GatewayRuntime`、`GatewaySessionsController`、`GatewayChatController`
- `AssistantPage` / `SettingsPage` 所有关键操作最终都回到 `AppController` 扩展层

### Side Effects

- 初始化 runtime、settings、account client、desktop service
- 维护 task thread、assistant session、本地 UI 状态
- 向 `GatewayAcpClient` 与 `GoTaskServiceClient` 注入 endpoint / auth 解析

### Notes

- 这里是 app 侧“唯一大脑”，但业务拆分主要通过 extension 文件完成
- 当前仓库已经收敛到 `assistant + settings`，不再承载旧模块壳

## `AppControllerDesktopNavigation`

- Source: `lib/app/app_controller_desktop_navigation.dart`
- Type: `extension`
- Responsibility:
  提供 destination 切换、settings/detail 打开关闭、sidebar 状态、语言与主题切换入口。

### Key Methods

| Method | Parameters | Returns | Meaning |
| --- | --- | --- | --- |
| `navigateTo` | `WorkspaceDestination destination` | `void` | 切到顶层页面 |
| `openSettings` | `{SettingsTab? tab, SettingsDetailPage? detail, SettingsNavigationContext? navigationContext}` | `void` | 打开 settings 并可直达 detail |
| `setSettingsTab` | `SettingsTab tab, {bool clearDetail=true}` | `void` | 切换 settings tab |
| `toggleAppLanguage` | none | `Future<void>` | 中英切换 |
| `setAppLanguage` | `AppLanguage language` | `Future<void>` | 显式保存语言 |
| `setThemeMode` | `ThemeMode mode` | `void` | 切换主题模式 |

### Main Call Chain

- `Sidebar` / `MobileShell` / focus panel -> navigation extension
- navigation extension -> `destinationInternal`, `settingsTabInternal`, `settingsDetailInternal`
- 状态更新后由 `AppShell` 与 `WorkspacePageSpec` 驱动实际页面构建

## `AppControllerDesktopSettings`

- Source: `lib/app/app_controller_desktop_settings.dart`
- Type: `extension`
- Responsibility:
  管理 settings draft、立即保存、apply、workspace path 更新，以及 assistant 本地状态清理。

### Key Methods

| Method | Parameters | Returns | Meaning |
| --- | --- | --- | --- |
| `saveSettingsDraft` | `SettingsSnapshot snapshot` | `Future<void>` | 更新草稿但不立即全局 apply |
| `persistSettingsDraft` | none | `Future<void>` | 把 draft 落到持久层 |
| `applySettingsDraft` | none | `Future<void>` | 将 draft 视为当前设置并触发副作用 |
| `saveSettings` | `SettingsSnapshot snapshot, {bool refreshAfterSave=true}` | `Future<void>` | 直接保存并按需刷新 |
| `saveWorkspacePath` | `String value` | `Future<void>` | 写工作区根路径 |
| `clearAssistantLocalState` | none | `Future<void>` | 清理本地 assistant/thread 相关状态 |

### Side Effects

- 写 `SecureConfigStore`
- 触发 runtime / gateway / provider catalog / thread persistence 的后续副作用
- 管理 token/password 等 secret draft

## `AppControllerDesktopSettingsRuntime`

- Source: `lib/app/app_controller_desktop_settings_runtime.dart`
- Type: `extension`
- Responsibility:
  把 settings 保存与 desktop/runtime 副作用连起来，包括 gateway catalog、VPN mode、授权目录、connection test。

### Key Methods

| Method | Parameters | Returns | Meaning |
| --- | --- | --- | --- |
| `updateAiGatewaySelection` | `List<String> selectedModels` | `Future<void>` | 归一化 AI gateway 选中模型并同步默认模型 |
| `syncAiGatewayCatalog` | `AiGatewayProfile profile, {String apiKeyOverride=''}` | `Future<AiGatewayProfile>` | 通过 settings controller 拉 catalog，回写 models controller |
| `refreshDesktopIntegration` | none | `Future<void>` | 刷新 desktop platform 状态 |
| `saveLinuxDesktopConfig` | `LinuxDesktopConfig config` | `Future<void>` | 保存 Linux tunnel/proxy 偏好 |
| `setDesktopVpnMode` | `VpnMode mode` | `Future<void>` | 持久化并切换 tunnel/proxy mode |
| `connectDesktopTunnel` | none | `Future<void>` | 发起 tunnel 连接 |
| `disconnectDesktopTunnel` | none | `Future<void>` | 断开 tunnel |
| `authorizeSkillDirectory` | `{String suggestedPath=''}` | `Future<AuthorizedSkillDirectory?>` | 授权单个 skill 目录 |
| `authorizeSkillDirectories` | `{List<String> suggestedPaths=const []}` | `Future<List<AuthorizedSkillDirectory>>` | 批量授权目录 |
| `testOllamaConnectionDraft` | `{required bool cloud, required SettingsSnapshot snapshot, String apiKeyOverride=''}` | `Future<String>` | 使用草稿参数测试连接 |

### Main Call Chain

- `SettingsPage` / quick actions -> settings runtime extension
- extension -> `SettingsController` / `DesktopPlatformService` / `SkillDirectoryAccessService`
- 成功后回写 `SettingsSnapshot`、`ModelsController`、task recompute

## `AppControllerDesktopThreadSessions`

- Source: `lib/app/app_controller_desktop_thread_sessions.dart`
- Type: `extension`
- Responsibility:
  承担 thread/session 级能力：artifact 读取、多 agent 协作启动、mount 刷新、online workspace 打开。

### Key Methods

| Method | Parameters | Returns | Meaning |
| --- | --- | --- | --- |
| `loadAssistantArtifactSnapshot` | `{String? sessionKey}` | `Future<AssistantArtifactSnapshot>` | 加载某会话 artifact 清单快照 |
| `loadAssistantArtifactPreview` | `AssistantArtifactEntry artifact, {String? sessionKey}` | `Future<AssistantArtifactPreview>` | 读取 artifact 预览内容 |
| `saveMultiAgentConfig` | `MultiAgentConfig config` | `Future<void>` | 持久化多 agent 配置 |
| `refreshMultiAgentMounts` | `{bool sync=false}` | `Future<void>` | 刷新或同步 mount |
| `runMultiAgentCollaboration` | named args | `Future<void>` | 触发多 agent 协作执行 |
| `openOnlineWorkspace` | none | `Future<void>` | 打开在线工作区入口 |

## `AppControllerDesktopWorkspaceExecution`

- Source: `lib/app/app_controller_desktop_workspace_execution.dart`
- Type: `extension`
- Responsibility:
  承担 assistant thread 的执行目标、provider、模型、权限、thread context、技能选择、任务归档主链。

### Key Methods

| Method | Parameters | Returns | Meaning |
| --- | --- | --- | --- |
| `setAssistantExecutionTarget` | `AssistantExecutionTarget target` | `Future<void>` | 切换当前 thread 的执行目标 |
| `setAssistantProvider` | `SingleAgentProvider provider` | `Future<void>` | 设置当前 thread 的 provider |
| `setAssistantMessageViewMode` | `AssistantMessageViewMode mode` | `Future<void>` | 切换 raw/rendered 视图 |
| `setAssistantPermissionLevel` | `AssistantPermissionLevel level` | `Future<void>` | 更新 assistant 权限档位 |
| `applyAssistantExecutionTargetInternal` | named args | `Future<void>` | 执行目标切换后的 thread/persistence 主逻辑 |
| `selectDefaultModel` | `String modelId` | `Future<void>` | 更新 settings 默认模型 |
| `selectAssistantModelForSession` | named args | `Future<void>` | 按 session 绑定模型 |
| `initializeAssistantThreadContext` | named args | `void` | 创建 thread 上下文骨架 |
| `toggleAssistantSkillForSession` | named args | `Future<void>` | 切换 thread 绑定技能 |
| `saveAssistantTaskArchived` | named args | `Future<void>` | 标记任务归档状态 |

### Main Call Chain

- `AssistantPage` composer / task dialog -> execution extension
- extension -> `ensureDesktopTaskThreadBindingInternal` / `upsertTaskThreadInternal`
- 最终通过 `GoTaskServiceClient`、`GatewayAcpClient`、gateway runtime 进入 bridge

## Runtime Coordination Helpers

- Source: `lib/app/app_controller_desktop_runtime_coordination_impl.dart`
- Type: `top-level functions`
- Responsibility:
  这些函数不是页面入口，但它们决定了 app 如何刷新 bridge 能力和重算任务视图。

### Key Functions

| Function | Parameters | Returns | Meaning |
| --- | --- | --- | --- |
| `refreshAcpCapabilitiesRuntimeInternal` | `AppController controller, {bool forceRefresh=false, bool persistMountTargets=false}` | `Future<void>` | 刷新 ACP capability snapshot |
| `refreshSingleAgentCapabilitiesRuntimeInternal` | `AppController controller, {bool forceRefresh=false}` | `Future<void>` | 刷新单 agent/provider catalog |
| `assistantWorkingDirectoryForSessionRuntimeInternal` | `AppController controller, String sessionKey` | `String?` | 求 session 工作目录 |
| `resolveLocalAssistantWorkingDirectoryForSessionRuntimeInternal` | `AppController controller, String sessionKey, {bool requireLocalExistence=true}` | `String?` | 返回本地且可用的工作目录 |
| `recomputeTasksRuntimeInternal` | `AppController controller` | `void` | 基于当前 session/thread/runtime 状态重建 task 列表 |

## `WorkspacePageSpec` and `buildWorkspacePage`

- Source: `lib/app/workspace_page_registry.dart`
- Type: `class` + `top-level function`
- Responsibility:
  这是 app 顶层 destination 到页面实现的唯一映射表。

### `WorkspacePageSpec` Parameters

| Param | Type | Required | Meaning |
| --- | --- | --- | --- |
| `destination` | `WorkspaceDestination` | Yes | page 所属目标 |
| `desktopBuilder` | `WorkspacePageBuilder` | Yes | 桌面构建器 |
| `mobileBuilder` | `WorkspacePageBuilder` | Yes | 移动端构建器 |

### `buildWorkspacePage`

| Parameters | Returns | Meaning |
| --- | --- | --- |
| `destination`, `controller`, `onOpenDetail`, `surface` | `Widget` | 根据 surface 选择 desktop/mobile page builder |

### Call Chain

- `AppShell` / `MobileShell` -> `buildWorkspacePage`
- `buildWorkspacePage` -> `AssistantPage` or `SettingsPage`

## `AppShell`

- Source: `lib/app/app_shell_desktop.dart`
- Type: `class`
- Responsibility:
  统一承载 desktop/mobile 分支、sidebar、detail drawer、destination rendering 和移动端 fallback 到 `MobileShell` 的切换。

### Constructor Parameters

| Param | Type | Required | Meaning |
| --- | --- | --- | --- |
| `controller` | `AppController` | Yes | 应用总控制器 |

### Returns

| API | Returns | Meaning |
| --- | --- | --- |
| `AppShell(...)` | `AppShell` | 顶层壳组件 |

### Main Call Chain

- `XWorkmateApp` -> `AppShell`
- `AppShell` -> `buildWorkspacePage` / `MobileShell`
- `AppShell` 同时消费 `SidebarTaskItem`、detail sheet、feature manifest 和 execution target 可见性
