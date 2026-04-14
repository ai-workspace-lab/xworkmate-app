# Feature Surfaces

## Purpose

本文件只写“关键页面和业务 surface”，不逐条解释视觉组件。页面层的原则是：

- `WorkspaceDestination` 是一级入口真源
- `WorkspacePageSpec` 是 destination 到页面实现的唯一映射
- 页面公开 API 只关注 controller 注入、detail 打开和业务入口参数

## `WorkspaceDestination`

- Source: `lib/models/app_models.dart`
- Type: `enum`
- Responsibility:
  当前顶层 surface 只有 `assistant` 与 `settings`。

### Returns

| Getter | Returns | Meaning |
| --- | --- | --- |
| `label` | `String` | 本地化标签 |
| `icon` | `IconData` | 导航图标 |
| `description` | `String` | 页面职责描述 |
| `fromJsonValue` | `WorkspaceDestination?` | 从持久化值恢复枚举 |

## `AssistantFocusEntry`

- Source: `lib/models/app_models.dart`
- Type: `enum`
- Responsibility:
  表示 Assistant 内可 pin 的 focus 入口，目前是 `settings / language / theme`。

### Returns

| Getter / API | Returns | Meaning |
| --- | --- | --- |
| `label` / `icon` / `description` | view metadata | focus 展示元数据 |
| `destination` | `WorkspaceDestination?` | 是否映射到真实 workspace 页面 |
| `opensSettingsPage` | `bool` | 是否最终进入 settings |
| `fromDestination` | `AssistantFocusEntry` | 从 destination 反解 focus entry |

## `SettingsNavigationContext`

- Source: `lib/models/app_models.dart`
- Type: `class`
- Responsibility:
  承担“从哪里进入 settings/detail”的 breadcrumb 和上下文信息。

### Constructor Parameters

| Param | Type | Required | Meaning |
| --- | --- | --- | --- |
| `rootLabel` | `String` | Yes | 顶层来源标签 |
| `destination` | `WorkspaceDestination` | Yes | 来源 destination |
| `sectionLabel` | `String?` | No | 中间 section 标签 |
| `settingsTab` | `SettingsTab?` | No | 目标 tab |
| `gatewayProfileIndex` | `int?` | No | 目标 gateway profile |
| `prefersGatewaySetupCode` | `bool?` | No | 是否优先 setup-code 流程 |

## `WorkspacePageSurface`

- Source: `lib/app/workspace_page_registry.dart`
- Type: `enum`
- Responsibility:
  区分 page builder 的 `desktop` 与 `mobile` surface。

## `WorkspacePageSpec`

- Source: `lib/app/workspace_page_registry.dart`
- Type: `class`
- Responsibility:
  把一个 destination 的桌面与移动 builder 绑定在一起。

### Constructor Parameters

| Param | Type | Required | Meaning |
| --- | --- | --- | --- |
| `destination` | `WorkspaceDestination` | Yes | 页面目标 |
| `desktopBuilder` | `WorkspacePageBuilder` | Yes | 桌面 builder |
| `mobileBuilder` | `WorkspacePageBuilder` | Yes | 移动 builder |

## `buildWorkspacePage`

- Source: `lib/app/workspace_page_registry.dart`
- Type: `top-level function`
- Responsibility:
  根据 destination 与 surface 实际实例化 `AssistantPage` / `SettingsPage`。

### Parameters and Returns

| Parameters | Returns | Meaning |
| --- | --- | --- |
| `destination`, `controller`, `onOpenDetail`, `surface` | `Widget` | 根据 `WorkspacePageSpec` 路由到具体页面 |

## `AssistantPage`

- Source: `lib/features/assistant/assistant_page_main.dart`
- Type: `class`
- Responsibility:
  承担桌面主工作台、timeline、composer、task rail、artifact pane、focus panel，以及所有 assistant 发起动作的 UI 主入口。

### Constructor Parameters

| Param | Type | Required | Default | Meaning |
| --- | --- | --- | --- | --- |
| `controller` | `AppController` | Yes | none | 统一业务控制器 |
| `onOpenDetail` | `ValueChanged<DetailPanelData>` | Yes | none | 打开 detail panel 的回调 |
| `navigationPanelBuilder` | `Widget Function(double contentWidth)?` | No | `null` | 定制导航区 |
| `showStandaloneTaskRail` | `bool` | No | `true` | 是否显示独立 task rail |
| `unifiedPaneStartsCollapsed` | `bool` | No | `false` | 初始化时 unified pane 是否折叠 |
| `clipboardImageReader` | `AssistantClipboardImageReader?` | No | `null` | 自定义剪贴板图像读取器 |

### Returns

| API | Returns | Meaning |
| --- | --- | --- |
| `AssistantPage(...)` | `AssistantPage` | assistant 顶层页面 |

### Main Call Chain

- `AppShell` / `WorkspacePageSpec` -> `AssistantPage`
- 页面内部通过 `AppControllerDesktopWorkspaceExecution`、`AppControllerDesktopThreadSessions` 发起执行、切换 provider、加载 artifact、多 agent 协作

### Notes

- 这里是关键页面，但其大量内部组件和 internal 状态机不作为本次文档展开对象

## `SettingsPage`

- Source: `lib/features/settings/settings_page_core.dart`
- Type: `class`
- Responsibility:
  承担 gateway、account、about 等配置型入口，并在保存后尝试刷新 bridge capabilities。

### Constructor Parameters

| Param | Type | Required | Default | Meaning |
| --- | --- | --- | --- | --- |
| `controller` | `AppController` | Yes | none | 应用控制器 |
| `initialTab` | `SettingsTab` | No | `SettingsTab.gateway` | 初始 tab |
| `initialDetail` | `SettingsDetailPage?` | No | `null` | 初始 detail |
| `navigationContext` | `SettingsNavigationContext?` | No | `null` | 导航上下文 |

### Main Call Chain

- `AppControllerDesktopNavigation.openSettings` -> `SettingsPage`
- `SettingsPage` -> `SettingsController.saveSnapshot/loginAccount/syncAccountSettings/verifyAccountMfa`
- 保存后最佳努力刷新 `refreshSingleAgentCapabilitiesInternal` 和 `refreshAcpCapabilitiesInternal`

## `MobileShell`

- Source: `lib/features/mobile/mobile_shell_core.dart`
- Type: `class`
- Responsibility:
  移动端的统一入口壳层，负责 tab 切换、pairing guide、setup code 连接流和 mobile-safe sheet。

### Constructor Parameters

| Param | Type | Required | Meaning |
| --- | --- | --- | --- |
| `controller` | `AppController` | Yes | 全局控制器 |

### Key Internal Business Entrypoints

| Method | Parameters | Returns | Meaning |
| --- | --- | --- | --- |
| `showConnectSheetInternal` | none | `void` | 打开 gateway connection detail |
| `openGatewaySetupCodeEntryInternal` | `{String? prefilledSetupCode}` | `Future<void>` | 进入 setup-code 输入流 |
| `connectWithScannedSetupCodeInternal` | `String setupCode` | `Future<void>` | 用扫码结果触发连接 |
| `showPairingGuidePageFlowInternal` | none | `Future<void>` | 打开 pairing guide 页面 |

### Notes

- `mobile_shell_strip.dart`、`mobile_shell_nav.dart`、`mobile_shell_sheet.dart` 等 leaf 组件不逐条展开

## `AppShell`

- Source: `lib/app/app_shell_desktop.dart`
- Type: `class`
- Responsibility:
  是 desktop/mobile surface 的统一宿主；在宽度不足时自动切到 `MobileShell`，在桌面场景下渲染 sidebar、detail 与 workspace 页面。

### Parameters and Returns

| Parameters | Returns | Meaning |
| --- | --- | --- |
| `controller: AppController` | `AppShell` | 顶层应用壳层 |
