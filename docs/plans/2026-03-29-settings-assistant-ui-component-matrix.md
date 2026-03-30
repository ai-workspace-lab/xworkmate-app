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

---

## 第二阶段评估：Web 页面分层哪些还值得继续收口

### A. `web_assistant_page_*`

当前文件规模：

- `lib/web/web_assistant_page_core.dart`：458 行
- `lib/web/web_assistant_page_chrome.dart`：471 行
- `lib/web/web_assistant_page_workspace.dart`：685 行
- `lib/web/web_assistant_page_helpers.dart`：277 行

#### 值得继续收口

1. `lib/web/web_assistant_page_workspace.dart`

- 这是当前最值得继续拆的文件。
- 同时承载：
  - 会话区主体
  - composer 区
  - session settings sheet
  - empty state
  - message bubble
  - side tab button
- 属于单文件内职责过多，但仍是纯 Web UI 视图层，适合继续按界面职责拆小。

建议下一步拆分：

- `web_assistant_page_messages.dart`
- `web_assistant_page_composer.dart`
- `web_assistant_page_session_sheet.dart`

2. `lib/web/web_assistant_page_chrome.dart`

- 值得做第二优先级收口。
- 当前同时承载：
  - 顶部 chrome
  - connection chip
  - 左侧任务 pane
  - conversation group 列表
- 这些部分都属于同一页面的 chrome 层，但已经接近“一个文件内多个子域”的边界。

建议下一步拆分：

- 保留 `web_assistant_page_chrome.dart` 作为组装入口
- 把 task pane / conversation group 提成独立子文件

#### 暂时不建议继续收口

1. `lib/web/web_assistant_page_core.dart`

- 虽然是状态 owner，但当前职责清晰：
  - controller 绑定
  - attachments
  - prompt submit
  - rename / action dialog
  - artifact pane 宽度与可见性
- 这部分是页面 orchestrator，不适合和 Desktop Assistant 强行合并。

2. `lib/web/web_assistant_page_helpers.dart`

- 文件规模适中，职责也比较稳定。
- 主要是 UI 原子和小模型定义，目前没有明显继续拆分收益。

#### 结论

- `web_assistant_page_*` 值得继续收口，但方向应是“Web 页面内部再拆职责”，不是“强行向 Desktop Assistant 页面合并”。

### B. `web_settings_page_*`

当前文件规模：

- `lib/web/web_settings_page_core.dart`：296 行
- `lib/web/web_settings_page_sections.dart`：403 行
- `lib/web/web_settings_page_gateway.dart`：813 行
- `lib/web/web_settings_page_support.dart`：92 行

#### 值得继续收口

1. `lib/web/web_settings_page_gateway.dart`

- 这是第二阶段里最值得继续动的文件。
- 已经超过 800 行，而且同时承载：
  - gateway overview
  - direct / local / remote gateway card
  - external ACP provider card
  - top-level apply 行为
  - wizard 逻辑
- 这是典型的“业务闭包过大但仍可按职责拆分”的目标。

建议下一步拆分：

- `web_settings_page_gateway_cards.dart`
- `web_settings_page_gateway_acp.dart`
- `web_settings_page_gateway_actions.dart`

2. `lib/web/web_settings_page_sections.dart`

- 值得轻量收口，但不是最高优先级。
- 现在已经共享了 shell 层，剩下的是 tab 内容组织和一些 overview 卡片。
- 更适合在 `web_settings_page_gateway.dart` 拆完后再回头看哪些 section 能继续下沉到共享层。

#### 暂时不建议继续收口

1. `lib/web/web_settings_page_core.dart`

- 这是 Web settings 的状态 owner。
- 当前规模不大，controller 同步逻辑和页面 frame 都还在合理范围内。
- 不建议为了“看起来统一”而和 Desktop `SettingsPage` 硬合。

2. `lib/web/web_settings_page_support.dart`

- 只有少量 support 工具和状态 chip。
- 保持现状即可。

#### 结论

- `web_settings_page_*` 里真正值得继续收口的是 `web_settings_page_gateway.dart`。
- `WebSettingsPage` 不值得直接向 `SettingsPage` 硬合；更合理的方向是继续抽共享 section/card 结构，而不是统一 controller。

### 第二阶段建议执行顺序

1. 先拆 `lib/web/web_settings_page_gateway.dart`
2. 再拆 `lib/web/web_assistant_page_workspace.dart`
3. 最后评估 `lib/web/web_assistant_page_chrome.dart` 和 `lib/web/web_settings_page_sections.dart`

这样收益最高，也最不容易碰到跨平台状态耦合。
