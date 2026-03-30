# XWorkmate UI 组件盘点与清理基线

## 目标

基于当前截图批次，收口以下主链路的 UI 组件归属与清理候选：

1. Assistant 三栏工作区
2. 设置页
3. 账号页
4. `SKILLS 目录授权`

本文档只记录当前实际代码状态，不再保留已完成清理前的旧副本描述。

---

## 在用的组件

| 名称 | 路径 | Desktop | Web | Mobile |
| --- | --- | --- | --- | --- |
| App Shell Desktop | `lib/app/app_shell_desktop.dart` | Yes | No | No |
| App Shell Web | `lib/app/app_shell_web.dart` | No | Yes | No |
| Mobile Shell | `lib/features/mobile/mobile_shell_core.dart` | No | No | Yes |
| Mobile Workspace Launcher | `lib/features/mobile/mobile_shell_workspace.dart` | No | No | Yes |
| Assistant Page | `lib/features/assistant/assistant_page_main.dart` | Yes | No | Yes |
| Assistant 主工作区拼装 | `lib/features/assistant/assistant_page_state_closure.dart` | Yes | No | Yes |
| Assistant 左侧关注面板 | `lib/widgets/assistant_focus_panel_core.dart` | Yes | No | No |
| Assistant 设置预览 | `lib/widgets/assistant_focus_panel_previews.dart` | Yes | No | No |
| Assistant 设置快捷操作 | `lib/widgets/settings_focus_quick_actions.dart` | Yes | Yes | No |
| 右侧任务文件栏 | `lib/widgets/assistant_artifact_sidebar.dart` | Yes | Yes | No |
| Desktop / Web 通用壳层 | `lib/widgets/desktop_workspace_scaffold.dart` | Yes | Yes | No |
| Settings Page | `lib/features/settings/settings_page_core.dart` | Yes | No | Yes |
| Settings Page sections | `lib/features/settings/settings_page_sections.dart` | Yes | No | Yes |
| Settings Page widgets | `lib/features/settings/settings_page_widgets.dart` | Yes | No | Yes |
| Gateway settings | `lib/features/settings/settings_page_gateway.dart` | Yes | No | Yes |
| Gateway connection settings | `lib/features/settings/settings_page_gateway_connection.dart` | Yes | No | Yes |
| Web Settings Page | `lib/web/web_settings_page_core.dart` | No | Yes | No |
| Web Settings sections | `lib/web/web_settings_page_sections.dart` | No | Yes | No |
| Web Settings gateway | `lib/web/web_settings_page_gateway.dart` | No | Yes | No |
| Web Settings support | `lib/web/web_settings_page_support.dart` | No | Yes | No |
| Account Page | `lib/features/account/account_page.dart` | Yes | No | Yes |
| Section Tabs | `lib/widgets/section_tabs.dart` | Yes | Yes | Yes |
| Top Bar | `lib/widgets/top_bar.dart` | Yes | Yes | Yes |
| Surface Card | `lib/widgets/surface_card.dart` | Yes | Yes | Yes |
| Skill Directory Authorization Card | `lib/features/settings/skill_directory_authorization_card.dart` | Yes | No | Yes |
| Settings Shell wrapper | `lib/widgets/settings_page_shell.dart` | Yes | Yes | Yes |

---

## 可以删除的 UI 组件

| 名称 | 路径 | 原因 |
| --- | --- | --- |
| 旧 Web Assistant 页面分层 | `lib/web/web_assistant_page_*` 中重复的局部壳层 | 只有在 Web Assistant 进一步向共享页面收口时才继续删。 |
| 旧设置页 Web 分层 | `lib/web/web_settings_page_*` 中重复的局部壳层 | 只有在 Web 设置页完全收口到共享 `SettingsPage` 后才建议删。 |

说明：

- `web_focus_panel_core.dart`
- `web_focus_panel_previews.dart`
- `web_focus_panel_support.dart`

这三份旧 Web Focus Panel 副本已经不再存在，不再列入候选池。

---

## 当前清理状态

### 第一批：已完成

- Web Focus Panel 共享化已收口到 `lib/widgets/assistant_focus_panel*.dart`
- Web Assistant 不再通过单独的 `web_focus_panel.dart` 兼容壳间接引用共享组件

### 第二批：已完成公共壳层收口

Desktop 与 Web 设置页当前已共用：

- `SettingsPageBodyShell`
- `SettingsGlobalApplyCard`
- `buildOrderedSettingsSections`

剩余差异集中在 controller、gateway 细节和 Web 专属 persistence 逻辑，不属于“已完成共享化的重复实现”。

### 第三批：本轮完成

- `IosMobileShell` 兼容壳删除后，以 `MobileShell` 作为唯一正式入口

### 第四批：持续维护

- 文档和测试应只引用当前仍存在的 UI 文件
- 不再记录已经删除的旧 Web Focus Panel 副本路径
