# Focus Panel Dedupe Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 在保持 Assistant 三栏布局骨架不变的前提下，收敛 Desktop / Web 重复的 Focus Panel 实现，建立共享前端组件单一来源。

**Architecture:** 保留 `lib/widgets/assistant_focus_panel*.dart` 作为唯一实现，Web 端改为直接复用共享 widgets，不再维护同构副本。先处理 Focus Panel Core / Previews / Support，再调整 Web Assistant 侧的 import 和引用，最后更新测试与文档。

**Tech Stack:** Flutter, Dart, conditional export `app_controller.dart`, widget tests, browser tests

---

### Task 1: 记录当前实施上下文

**Files:**
- Modify: `docs/plans/2026-03-29-settings-assistant-ui-component-matrix.md`
- Create: `docs/plans/2026-03-29-focus-panel-dedupe-implementation-plan.md`

**Step 1: 追加“可合并 / 可清理分析”**

把本轮结论写入组件矩阵文档：

- 可直接合并：Focus Panel Core / Previews / Support
- 可抽公共层：Settings Page Core / Sections
- 可标记清理：Web Focus Panel 副本、deprecated iOS shell、settings detail 旁路

**Step 2: 记录基线测试**

记录：

- `flutter test test/widgets/assistant_focus_panel_suite.dart` 通过
- `flutter test --platform chrome test/web/web_ui_browser_test.dart` 当前基线失败，失败点为找不到 “集成” tab

### Task 2: 建立共享 Focus Panel 单一实现

**Files:**
- Modify: `lib/widgets/assistant_focus_panel.dart`
- Modify: `lib/widgets/assistant_focus_panel_core.dart`
- Modify: `lib/widgets/assistant_focus_panel_previews.dart`
- Modify: `lib/widgets/assistant_focus_panel_support.dart`
- Modify: `lib/web/web_assistant_page_core.dart`
- Modify: `lib/web/web_assistant_page_chrome.dart`
- Modify: `lib/web/web_assistant_page_workspace.dart`
- Modify: `lib/web/web_assistant_page_helpers.dart`

**Step 1: 让 Web 侧直接依赖共享入口**

把 Web Assistant 页面中对 `web_focus_panel.dart` 的依赖改成共享 `../widgets/assistant_focus_panel.dart`。

**Step 2: 去掉 Web 专属 Focus Panel 类型耦合**

把 `WebAssistantFocusPanel` 的使用点替换为 `AssistantFocusPanel`。

**Step 3: 确认共享组件继续使用条件导出的 controller**

共享 Focus Panel 通过 `../app/app_controller.dart` 获取平台适配后的 `AppController`，不再区分 Desktop/Web 文件树。

### Task 3: 退役 Web Focus Panel 副本

**Files:**
- Delete: `lib/web/web_focus_panel_core.dart`
- Delete: `lib/web/web_focus_panel_previews.dart`
- Delete: `lib/web/web_focus_panel_support.dart`
- Modify: `lib/web/web_focus_panel.dart`

**Step 1: 保留一个薄入口或直接删入口**

推荐做法：

- `lib/web/web_focus_panel.dart` 变成一行导出共享 widget 的兼容入口

```dart
export '../widgets/assistant_focus_panel.dart';
```

**Step 2: 删除三份重复副本**

删除：

- `web_focus_panel_core.dart`
- `web_focus_panel_previews.dart`
- `web_focus_panel_support.dart`

### Task 4: 更新测试与守护规则

**Files:**
- Modify: `test/widgets/assistant_focus_panel_suite.dart`
- Verify: `test/web/web_ui_browser_test.dart`

**Step 1: 更新文件存在性 / 行数守护**

将原来对 Web 重复文件的守护改成对共享实现的守护，避免测试继续依赖已删除文件路径。

**Step 2: 跑 widget 测试**

Run:

```bash
flutter test test/widgets/assistant_focus_panel_suite.dart
```

Expected:

- PASS

**Step 3: 跑 browser 测试并记录结果**

Run:

```bash
flutter test --platform chrome test/web/web_ui_browser_test.dart
```

Expected:

- 如果仍失败，需要确认是否仍是既有 “集成” tab 失败
- 如果失败点变化，说明本轮重构影响了 Web 链路，需要回退排查

### Task 5: 回归与提交

**Files:**
- Verify only

**Step 1: 检查 git diff**

确认本轮只涉及：

- 文档
- Focus Panel 共享化
- 测试更新

**Step 2: 记录 residual risks**

记录：

- `SettingsPage` / `WebSettingsPage` 尚未统一
- `settings detail flow` 仍在 Desktop overview 体系里
- `ios_mobile_shell.dart` 仍未清理

**Step 3: 提交**

建议提交信息：

```bash
git commit -m "refactor: dedupe assistant focus panel across desktop and web"
```
