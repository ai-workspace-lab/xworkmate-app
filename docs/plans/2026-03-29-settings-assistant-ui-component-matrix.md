# XWorkmate 设置页与 Assistant 三栏 UI 组件梳理

## 目标

结合本次两张截图，对应梳理：

1. 截图 A：Assistant 三栏工作区中的“设置焦点卡片 + 会话区 + 右侧任务文件栏”
2. 截图 B：完整“设置”页
3. 这些 UI 在 Desktop / Web / Mobile 三端的代码归属与复用关系

---

## 截图归因

### 截图 A：Assistant 三栏工作区

这张图对应的是桌面端 Assistant 主工作区，不是完整设置页。

代码链路是：

- `lib/app/app_shell_desktop.dart`
  Desktop 壳层负责把当前路由切到 `WorkspaceDestination.assistant`
- `lib/app/workspace_page_registry.dart`
  把 Assistant 路由映射到 `AssistantPage`
- `lib/features/assistant/assistant_page_main.dart`
  负责三栏布局骨架：
  - 左侧：`AssistantUnifiedSidePaneInternal`
  - 中间：主会话工作区
  - 右侧：任务文件/预览栏
- `lib/widgets/assistant_focus_panel_core.dart`
  左侧“关注入口”卡片容器
- `lib/widgets/assistant_focus_panel_previews.dart`
  其中“设置”卡片内部内容来自 `SettingsFocusPreviewInternal`
- `lib/widgets/settings_focus_quick_actions.dart`
  语言切换、主题切换两个快捷按钮
- `lib/features/assistant/assistant_page_state_closure.dart`
  中间消息区、输入区、右侧产物栏拼装逻辑
- `lib/widgets/assistant_artifact_sidebar.dart`
  右侧“当前任务工作路径 / 全部文件 / 预览 / 暂无文件”侧栏

### 截图 B：完整设置页

这张图对应的是桌面端完整设置页。

代码链路是：

- `lib/app/app_shell_desktop.dart`
  壳层负责把当前路由切到 `WorkspaceDestination.settings`
- `lib/app/workspace_page_registry.dart`
  把设置路由映射到 `SettingsPage`
- `lib/features/settings/settings_page_core.dart`
  整个设置页主容器，负责：
  - Breadcrumb / 标题 / 搜索框
  - 顶部保存入口
  - Tab 区域
  - 各 section 内容装配
- `lib/features/settings/settings_page_sections.dart`
  负责：
  - `buildGlobalApplyBarInternal`：“设置提交流程 / 保存并生效”
  - `buildGeneralInternal`：`Application`、`账号访问` 等卡片
- `lib/features/settings/settings_page_widgets.dart`
  负责通用字段原子组件：
  - `SwitchRowInternal`
  - `EditableFieldInternal`
  - `InfoRowInternal`
- `lib/widgets/section_tabs.dart`
  “通用 / 工作区 / 集成 / 外观 / 诊断 / 关于” tab 条
- `lib/widgets/top_bar.dart`
  页面顶部 breadcrumb、标题、副标题、搜索框区域

---

## UI 组件矩阵

| UI Name | code path | Desktop | Web | Mobile |
| --- | --- | --- | --- | --- |
| Desktop App Shell | `lib/app/app_shell_desktop.dart` | Yes | No | No |
| Web App Shell | `lib/app/app_shell_web.dart` | No | Yes | No |
| Mobile Shell | `lib/features/mobile/mobile_shell_core.dart` | No | No | Yes |
| Assistant Page | `lib/features/assistant/assistant_page_main.dart` | Yes | No | Yes |
| Assistant 主工作区拼装 `buildMainWorkspaceInternal` | `lib/features/assistant/assistant_page_state_closure.dart` | Yes | No | Yes |
| Assistant 右侧产物栏拼装 `buildWorkspaceWithArtifactsInternal` | `lib/features/assistant/assistant_page_state_closure.dart` | Yes | No | Yes |
| Assistant 统一左侧板 `AssistantUnifiedSidePaneInternal` | `lib/features/assistant/assistant_page_main.dart` | Yes | No | No |
| Assistant 关注入口面板 `AssistantFocusPanel` | `lib/widgets/assistant_focus_panel_core.dart` | Yes | No | No |
| 设置焦点预览 `SettingsFocusPreviewInternal` | `lib/widgets/assistant_focus_panel_previews.dart` | Yes | No | No |
| 设置快捷操作 `SettingsFocusQuickActions` | `lib/widgets/settings_focus_quick_actions.dart` | Yes | Yes | No |
| 任务文件侧栏 `AssistantArtifactSidebar` | `lib/widgets/assistant_artifact_sidebar.dart` | Yes | Yes | No |
| Desktop / Web 通用内容卡片壳 `DesktopWorkspaceScaffold` | `lib/widgets/desktop_workspace_scaffold.dart` | Yes | Yes | No |
| 完整设置页 `SettingsPage` | `lib/features/settings/settings_page_core.dart` | Yes | No | Yes |
| 设置页顶部栏 `TopBar` | `lib/widgets/top_bar.dart` | Yes | Yes | Yes |
| 设置提交流程条 `buildGlobalApplyBarInternal` | `lib/features/settings/settings_page_sections.dart` | Yes | No | Yes |
| 设置页通用卡片 `buildGeneralInternal` | `lib/features/settings/settings_page_sections.dart` | Yes | No | Yes |
| 设置表单原子 `SwitchRowInternal / EditableFieldInternal` | `lib/features/settings/settings_page_widgets.dart` | Yes | No | Yes |
| 设置页标签条 `SectionTabs` | `lib/widgets/section_tabs.dart` | Yes | Yes | Yes |
| Web Assistant Page | `lib/web/web_assistant_page_core.dart` | No | Yes | No |
| Web Assistant 顶部 chrome | `lib/web/web_assistant_page_chrome.dart` | No | Yes | No |
| Web Assistant 会话工作区 | `lib/web/web_assistant_page_workspace.dart` | No | Yes | No |
| Web 关注入口面板 `WebAssistantFocusPanel` | `lib/web/web_focus_panel_core.dart` | No | Yes | No |
| Web 设置页 `WebSettingsPage` | `lib/web/web_settings_page_core.dart` | No | Yes | No |
| Web 设置页 section 装配 | `lib/web/web_settings_page_sections.dart` | No | Yes | No |
| Mobile 工作区入口 `MobileWorkspaceLauncherInternal` | `lib/features/mobile/mobile_shell_workspace.dart` | No | No | Yes |

---

## 截图 A 对应的关键组件名字

### 左侧窄图标列

桌面截图 A 左边最窄的图标列，对应：

- `AssistantSideTabRailInternal`
- `AssistantSideTabButtonInternal`

代码文件：

- `lib/features/assistant/assistant_page_main.dart`

它不是全局设置页导航，而是 Assistant 工作区内部的“任务 / 导航 / 关注入口”侧板。

### 左侧“设置”卡片

左侧大卡片不是完整设置页，而是 Assistant 中的一个“关注入口工作台卡片”：

- 卡片容器：`AssistantFocusWorkbenchInternal`
- 设置摘要内容：`SettingsFocusPreviewInternal`
- 顶部快捷按钮：`SettingsFocusQuickActions`

对应文件：

- `lib/widgets/assistant_focus_panel_core.dart`
- `lib/widgets/assistant_focus_panel_previews.dart`
- `lib/widgets/settings_focus_quick_actions.dart`

截图里出现的这些文案都直接来自 `SettingsFocusPreviewInternal`：

- `设置`
- `语言`
- `主题`
- `执行目标`
- `权限`

### 中间会话区

中间对话工作区对应：

- 页面骨架：`AssistantPage`
- 主体拼装：`buildMainWorkspaceInternal`

对应文件：

- `lib/features/assistant/assistant_page_main.dart`
- `lib/features/assistant/assistant_page_state_closure.dart`

这一块负责：

- 顶部会话流
- 消息气泡
- 底部输入区
- 附件 / 技能 / 提交按钮

### 右侧任务文件栏

右侧栏对应：

- `AssistantArtifactSidebar`

对应文件：

- `lib/widgets/assistant_artifact_sidebar.dart`

截图里的这些元素都在这个组件中：

- `当前任务工作路径`
- `全部文件`
- `预览`
- `暂无文件`

---

## 截图 B 对应的关键组件名字

### 设置页整体

完整页面组件名：

- `SettingsPage`

对应文件：

- `lib/features/settings/settings_page_core.dart`

它负责：

- 顶部 breadcrumb
- 标题 `设置`
- 副标题
- 搜索框 `搜索设置`
- 页面 section 排布

### 顶部“设置提交流程”

组件来源：

- `buildGlobalApplyBarInternal`

对应文件：

- `lib/features/settings/settings_page_sections.dart`

截图里的：

- `设置提交流程`
- `当前没有待提交更改。`
- `保存并生效`

都来自这里。

### Tab 区域

组件名：

- `SectionTabs`

对应文件：

- `lib/widgets/section_tabs.dart`

截图里的：

- `通用`
- `工作区`
- `集成`
- `外观`
- `诊断`
- `关于`

都由这个组件承载。

### Application 与账号访问卡片

组件来源：

- `buildGeneralInternal`
- 原子行组件：`SwitchRowInternal`
- 输入组件：`EditableFieldInternal`

对应文件：

- `lib/features/settings/settings_page_sections.dart`
- `lib/features/settings/settings_page_widgets.dart`

截图里这些内容都在这部分：

- `Application`
- `启用工作台外壳`
- `开机启动`
- `显示 Dock 图标`
- `账号本地模式`
- `账号访问`
- `账号服务地址`
- `账号用户名`
- `工作区名称`

---

## 跨端设计结论

### 1. Desktop 与 Web 共用“视觉原子”，但页面容器分裂

以下组件明显是跨端复用的：

- `DesktopWorkspaceScaffold`
- `SurfaceCard`
- `TopBar`
- `SectionTabs`
- `SettingsFocusQuickActions`
- `AssistantArtifactSidebar`

但 Desktop 与 Web 的页面级容器并没有统一：

- Desktop 设置页：`SettingsPage`
- Web 设置页：`WebSettingsPage`
- Desktop Assistant：`AssistantPage`
- Web Assistant：`WebAssistantPage`

这意味着视觉语言接近，但页面编排逻辑仍然是双实现。

### 2. Mobile 不是截图同构，而是能力映射

Mobile 当前不是截图 A / B 的直接缩放版，而是“能力对应、布局重组”：

- Assistant 与设置功能仍然存在
- 但入口通过 `MobileShell` 和 `MobileWorkspaceLauncherInternal` 组织
- 不存在截图 A 这种桌面三栏结构
- 设置页在 Mobile 继续复用 `SettingsPage`

所以从设计维护角度看：

- `SettingsPage` 是 Desktop / Mobile 的共享设置容器
- `WebSettingsPage` 是 Web 独立实现
- `AssistantArtifactSidebar` 是 Desktop / Web 共享产物侧栏
- “设置焦点卡片”只存在于 Desktop / Web 的 Assistant 焦点面板体系里，不属于 Mobile

### 3. 如果后续要统一三端设计，优先收敛这三层

建议优先把以下三层当作设计系统主干：

1. 页面骨架层：`DesktopWorkspaceScaffold` / `TopBar`
2. section 层：`SectionTabs` / `SurfaceCard`
3. 领域卡片层：设置卡、焦点卡、产物栏

其中最值得继续收敛的重复实现是：

- `SettingsPage` vs `WebSettingsPage`
- `AssistantFocusPanel` vs `WebAssistantFocusPanel`
- `assistant_focus_panel_previews.dart` vs `web_focus_panel_previews.dart`

---

## 建议的后续文档演进

如果后续继续补 UI 文档，建议按下面三个文件拆：

1. `assistant-layout-spec.md`
   只描述 Assistant 三栏布局、会话区、产物栏
2. `settings-page-spec.md`
   只描述设置页 section、字段、交互状态
3. `cross-platform-ui-parity.md`
   专门记录 Desktop / Web / Mobile 的同构与差异

---

## 可合并 / 可清理分析

在保持三栏布局骨架不变的前提下，当前最值得处理的不是页面骨架，而是页面骨架内部已经重复的“焦点卡片层”和“预览内容层”。

### A. 第一优先级：可直接合并复用

#### 1. Focus Panel Core

- Desktop: `lib/widgets/assistant_focus_panel_core.dart`
- Web: `lib/web/web_focus_panel_core.dart`

这两份文件当前为同构重复实现。

判断依据：

- 文件长度完全一致，均为 `347` 行
- 代码 diff 主要只剩：
  - `app_controller.dart` vs `app_controller_web.dart`
  - 相对 import 路径差异
  - widget 命名前缀 `Assistant*` vs `WebAssistant*`

合并建议：

- 保留 `lib/widgets/assistant_focus_panel*.dart` 作为唯一实现
- Web 端直接复用共享 widget
- 删除 Web 侧同构副本，或先退化为兼容导出薄壳

#### 2. Focus Panel Previews

- Desktop: `lib/widgets/assistant_focus_panel_previews.dart`
- Web: `lib/web/web_focus_panel_previews.dart`

这两份文件当前也为同构重复实现。

判断依据：

- 文件长度完全一致，均为 `636` 行
- diff 也只剩 controller import 和路径差异
- `SettingsFocusPreviewInternal`、`LanguageFocusPreviewInternal`、`ThemeFocusPreviewInternal` 等实现一致

合并建议：

- 收敛到 `lib/widgets/assistant_focus_panel_previews.dart`
- Web Assistant 通过共享导出的 `AssistantFocusPanel` 直接复用

#### 3. Focus Panel Support

- Desktop: `lib/widgets/assistant_focus_panel_support.dart`
- Web: `lib/web/web_focus_panel_support.dart`

这两份 support 文件同样是同构副本，可和 core / previews 一起收口。

### B. 第二优先级：可抽公共层，但不建议整页硬合并

#### 1. Settings Page Core

- Desktop: `lib/features/settings/settings_page_core.dart`
- Web: `lib/web/web_settings_page_core.dart`

不建议直接合成一个页面类。

原因：

- Desktop settings 还承载 `SettingsDetailPage` drill-down、`initialDetail`、`navigationContext`
- Web settings 重点维护浏览器会话持久化、Local/Remote Gateway、External ACP
- 二者状态模型明显不对称

建议做法：

- 抽共享壳层和 section 编排逻辑
- 保留 Desktop / Web 两个 page container

#### 2. Settings Page Sections

- Desktop: `lib/features/settings/settings_page_sections.dart`
- Web: `lib/web/web_settings_page_sections.dart`

这里适合抽：

- `buildGlobalApplyBarInternal`
- overview tab 排布
- section 级 SurfaceCard 组织方式

但不适合一步到位强合并所有业务 section。

### C. 可标记清理

#### 1. Web Focus Panel 重复文件

以下文件可以标记为第一批清理对象：

- `lib/web/web_focus_panel_core.dart`
- `lib/web/web_focus_panel_previews.dart`
- `lib/web/web_focus_panel_support.dart`

清理前提：

- Web Assistant 全部切回共享 `lib/widgets/assistant_focus_panel.dart`
- 相关测试与 import 路径同步调整

#### 2. 已废弃 iOS 壳别名

- `lib/features/mobile/ios_mobile_shell.dart`

该文件已标注：

- `@Deprecated('Use MobileShell instead.')`

功能上只是直接转发到 `MobileShell`，可以标记为后续兼容清理对象。

#### 3. 不在这两张图主链路中的 settings detail 旁路

以下内容不属于截图 B 的 overview 主链路，建议后续拆出：

- `buildDetailContentInternal`
- `buildDetailIntroInternal`
- `SettingsDetailPage.*`

对应文件：

- `lib/features/settings/settings_page_sections.dart`

这些应独立成 detail flow 文件，而不是继续和 overview 同居在一个大文件里。

#### 4. settings 目录中的大面积冗余 import

当前以下文件头部都带有较重的 `unused_import` / 互相引用信号：

- `lib/features/settings/settings_page_core.dart`
- `lib/features/settings/settings_page_sections.dart`
- `lib/features/settings/settings_page_widgets.dart`
- `lib/features/settings/settings_page_gateway_connection.dart`
- `lib/features/settings/settings_page_gateway_llm.dart`
- `lib/features/settings/settings_page_multi_agent.dart`
- `lib/features/settings/settings_page_presentation.dart`
- `lib/features/settings/settings_page_device.dart`

这些不是“立即删除”对象，但可以明确标记为依赖清理范围。

### D. 本轮推荐执行顺序

在不动三栏布局骨架前提下，推荐按这个顺序执行：

1. 合并 Desktop / Web 的 Focus Panel Core / Previews / Support
2. 抽 Settings 页的共享 section 壳层
3. 拆 Settings detail flow，避免与 overview 混杂
4. 清理 deprecated mobile 壳与 settings 冗余 imports

### E. 当前基线测试记录

本轮开始前的最小基线如下：

- `flutter test test/widgets/assistant_focus_panel_suite.dart`
  - 结果：通过
- `flutter test --platform chrome test/web/web_ui_browser_test.dart`
  - 结果：失败
  - 当前已知失败点：测试找不到 “集成” tab

因此后续重构验证需要区分：

- 共享 Focus Panel 的 widget 层回归
- Web 端已有基线失败，不能误判为本轮新引入问题
