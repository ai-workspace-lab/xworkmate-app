# Mobile iOS Bug Fix Session — 2026-07-15

> **Agent Session**: `d9233386-79e0-4029-9fe3-601bd015fd45`
> **Date**: 2026-07-15 (UTC+8)
> **Target Branches**: `release/v1.1`, `main`
> **Context**: Apple Review 准备期间的 iOS 移动端 Bug 修复与 UI 优化

---

## 目标概述

针对 Apple 审核专用账号 `review@svc.plus` 在 iOS 真机上暴露出的若干问题进行修复：

1. 附件选择器不可用
2. 技能列表未加载
3. 对话消息中的硬编码 UI（假 artifact 卡片、"查看运行日志" 按钮）
4. 执行进度截图调试问题

---

## 涉及文件总览

| 文件 | 路径 | 修改类型 |
|------|------|----------|
| `mobile_assistant_page_composer.dart` | `lib/features/mobile/` | 已修改 |
| `mobile_assistant_page_core.dart` | `lib/features/mobile/` | 已修改 |
| `mobile_assistant_page_conversation.dart` | `lib/features/mobile/` | 已修改 |

---

## Bug 1：附件选择器不可用

### 状态：✅ 已修复

### 问题描述

在 iOS 真机上登录 `review@svc.plus` 后，点击 `+` 号弹出配置面板，"添加附件" 按钮无法触发文件选择器。

### 根因

`MobileAssistantComposer` 之前的代码中，附件按钮直接放在了 Composer 内部，但在重构 `showConfigurationMenu` (BottomSheet) 时，附件按钮被移入 BottomSheet 中。BottomSheet 是独立的路由上下文，调用 `onPickAttachments()` 前必须先 `Navigator.pop(sheetContext)` 关闭面板，否则文件选择器会被 BottomSheet 的路由遮挡。

### 修复细节

#### 文件: [`mobile_assistant_page_composer.dart`](file:///Users/shenlan/workspaces/ai-workspace-lab/xworkmate-app/lib/features/mobile/mobile_assistant_page_composer.dart)

- **函数**: `showConfigurationMenu()` 内的 `MobileAssistantActionChip` (附件按钮)
- **位置**: 约 L235–L244
- **修改**: 在 `onTap` 回调中，先调用 `Navigator.pop(sheetContext)` 关闭 BottomSheet，再调用 `onPickAttachments()`

```dart
// L241-L244
onTap: () {
  Navigator.pop(sheetContext);  // 先关闭面板
  onPickAttachments();          // 再触发文件选择器
},
```

#### 文件: [`mobile_assistant_page_core.dart`](file:///Users/shenlan/workspaces/ai-workspace-lab/xworkmate-app/lib/features/mobile/mobile_assistant_page_core.dart)

- **函数**: `_pickAttachments()`
- **说明**: 该函数通过 `file_selector` 包调用系统文件选择器，本身逻辑无问题，只是被 BottomSheet 路由阻挡

### 相关 PR

- **PR #125** (已合并到 `release/v1.1`): `hotfix/mobile-ios-attachment-skills`

---

## Bug 2：技能列表未加载

### 状态：✅ 已修复

### 问题描述

在 iOS 真机上，点击 `+` 号弹出配置面板后，技能列表始终为空，显示"当前没有已加载技能"。但在 Desktop 端相同账号可以正常加载。

### 根因

`showConfigurationMenu` 通过 `showModalBottomSheet` 弹出，这是一个独立路由。弹出时 `controller.skills` 可能仍在异步加载中，一旦面板构建完毕，不会再自动监听 `controller` 的数据变化，导致技能数据加载完成后面板不会刷新。

### 修复细节

#### 文件: [`mobile_assistant_page_composer.dart`](file:///Users/shenlan/workspaces/ai-workspace-lab/xworkmate-app/lib/features/mobile/mobile_assistant_page_composer.dart)

- **函数**: `showConfigurationMenu()` 内的技能列表部分
- **位置**: 约 L278–L360
- **修改**: 将技能列表的整个 `Column` 包裹在 `AnimatedBuilder(animation: controller, ...)` 中，使得 `controller` 数据变化时自动触发 BottomSheet 内部 rebuild

```dart
// L278-L280
AnimatedBuilder(
  animation: controller,
  builder: (context, _) {
    if (controller.skills.isEmpty) {
      // 显示空状态提示
    }
    // 渲染技能 FilterChip 列表
  },
),
```

### 相关 PR

- **PR #125** (已合并到 `release/v1.1`): `hotfix/mobile-ios-attachment-skills`
- 注意: 该 PR 同时也已被 merge 到 `main` (通过直接合并 — 在后续 PR 规范化之前完成)

---

## Bug 3：硬编码 artifact 卡片和"查看运行日志"按钮

### 状态：✅ 已修复（PR 待合并）

### 问题描述

每条 Assistant 消息下方都固定显示:
1. 一个写死的 `_MobileGeneratedArtifactCard`，标题永远是 "任务结果.md"
2. 一个 `_MobileLogButton`，显示 "查看运行日志" 但没有任何实际功能

这两个硬编码组件让每条消息都显得杂乱，且 artifact 不是按真实数据动态渲染的。

### 修复细节

#### 文件: [`mobile_assistant_page_conversation.dart`](file:///Users/shenlan/workspaces/ai-workspace-lab/xworkmate-app/lib/features/mobile/mobile_assistant_page_conversation.dart)

##### 1. 新增 import

- **位置**: L1, L12
- **修改**: 添加 `import 'dart:async';` 和 `import '../../runtime/assistant_artifacts.dart';`

##### 2. 移除每条消息内的硬编码卡片

- **类**: `_MobileAssistantMessageCard`
- **位置**: 原 L214–L250 区域
- **修改**: 从 `_MobileAssistantMessageCard.build()` 中删除了 `_MobileGeneratedArtifactCard` 和 `_MobileLogButton`，保留 `_MobileBridgeInlineStatus`

##### 3. 修改 ListView 增加动态 artifact 尾部项

- **类**: `MobileAssistantConversation`
- **函数**: `build()`
- **位置**: L47–L62
- **修改**: `itemCount` 从 `itemCount` 改为 `itemCount + 1`，在 `itemBuilder` 最末追加 `_MobileSessionArtifacts(controller: controller)` 作为列表最后一项

```dart
// L54-L59
itemCount: itemCount + 1,
separatorBuilder: (_, _) => const SizedBox(height: 18),
itemBuilder: (context, index) {
  if (index == itemCount) {
    return _MobileSessionArtifacts(controller: controller);
  }
  // ...
},
```

##### 4. 新增 `_MobileSessionArtifacts` 组件

- **位置**: L838–L910
- **类型**: `StatefulWidget`
- **功能**: 每 3 秒通过 `controller.loadAssistantArtifactSnapshot()` 轮询当前会话的真实 artifact 列表，动态渲染
- **关键函数**:
  - `initState()`: 初始化并启动 `Timer.periodic(Duration(seconds: 3), ...)`
  - `dispose()`: 取消定时器
  - `_load()`: 异步调用 `loadAssistantArtifactSnapshot()`，成功后 `setState`
  - `build()`: 如无 artifact 返回 `SizedBox.shrink()`；有数据则遍历 `_snapshot!.fileEntries`，每个 entry 渲染一个 `_MobileGeneratedArtifactCard`

##### 5. 修改 `_MobileGeneratedArtifactCard`

- **位置**: L765–L837
- **修改**: 
  - 新增 `required String title` 参数（替代硬编码的 "任务结果.md"）
  - `onTap` 改为 `required VoidCallback`（原为可空 `VoidCallback?`）

##### 6. 删除 `_MobileLogButton`

- **整个类已删除**: 原 L864–L895
- **原因**: "查看运行日志" 按钮没有实际功能跳转，属于错误设计

##### 7. 简化 `_MobileExecutionProgressCard` 提示文案

- **位置**: L254–L258
- **修改**: 将 `'正在生成中...你可以随时查看日志或取消任务。'` 简化为 `'正在执行中...'`

##### 8. 删除 `_MobileExecutionTimeline` 和相关类

- **已删除的类**: `_MobileExecutionTimeline`, `_TimelineStep`, `_MobileTimelineRow`
- **原因**: 这些是硬编码的执行进度时间线，不与真实后端数据挂钩

### 相关 PR

| PR | 分支 | 目标分支 | 状态 |
|----|------|----------|------|
| [#126](https://github.com/ai-workspace-lab/xworkmate-app/pull/126) | `hotfix/mobile-dynamic-artifacts` | `release/v1.1` | 🟡 OPEN — 待合并 |
| [#127](https://github.com/ai-workspace-lab/xworkmate-app/pull/127) | `cherry-pick/mobile-dynamic-artifacts` | `main` | 🟡 OPEN — 待合并 |

---

## 关键数据模型引用

| 类型 | 文件 | 说明 |
|------|------|------|
| `AssistantArtifactSnapshot` | [`lib/runtime/assistant_artifacts.dart`](file:///Users/shenlan/workspaces/ai-workspace-lab/xworkmate-app/lib/runtime/assistant_artifacts.dart) L162 | 包含 `fileEntries` 列表，每项有 `label` 字段 |
| `loadAssistantArtifactSnapshot()` | [`lib/app/app_controller_desktop_thread_sessions.dart`](file:///Users/shenlan/workspaces/ai-workspace-lab/xworkmate-app/lib/app/app_controller_desktop_thread_sessions.dart) L378 | 从运行时加载当前会话的 artifact 快照 |
| `loadAssistantArtifactPreview(entry)` | 同上 | 加载单个 artifact 的预览内容，返回含 `.content` 字段 |
| `GatewayChatMessage` | [`lib/runtime/runtime_models_runtime_payloads.dart`](file:///Users/shenlan/workspaces/ai-workspace-lab/xworkmate-app/lib/runtime/runtime_models_runtime_payloads.dart) L308 | 聊天消息模型，含 `role`, `text`, `pending`, `error` 等字段 |
| `controller.skills` | [`lib/app/app_controller_desktop_core.dart`](file:///Users/shenlan/workspaces/ai-workspace-lab/xworkmate-app/lib/app/app_controller_desktop_core.dart) | ACP 技能列表，异步加载后通过 `notifyListeners()` 通知 |

---

## 任务清单

### ✅ 已完成

- [x] 修复 iOS 附件选择器不可用 (Bug 1)
- [x] 修复 iOS 技能列表未加载 (Bug 2)
- [x] 移除硬编码 artifact 卡片和日志按钮 (Bug 3)
- [x] 新增 `_MobileSessionArtifacts` 动态 artifact 组件
- [x] 修改 `_MobileGeneratedArtifactCard` 支持动态标题
- [x] 删除无功能的 `_MobileLogButton` 和 `_MobileExecutionTimeline`
- [x] 简化 `_MobileExecutionProgressCard` 文案
- [x] Bug 1 & 2 提交到 `release/v1.1` 和 `main` 并合并
- [x] Bug 3 创建 PR #126 (`release/v1.1`) 和 PR #127 (`main`)

### 🟡 进行中 / 待确认

- [ ] **合并 PR #126 和 PR #127** — 需要代码审查后合并
- [ ] **真机验证** — Bug 3 修复后已触发 `flutter run --release`（编译成功），但需要人工在 iOS 真机上验证动态 artifact 渲染

### 📋 后续建议

- [ ] `_MobileSessionArtifacts` 的轮询间隔（当前 3 秒）可优化为事件驱动，监听 `controller` 的 `notifyListeners` 而非定时器
- [ ] 合并 PR 后清理远端临时分支: `hotfix/mobile-dynamic-artifacts`, `cherry-pick/mobile-dynamic-artifacts`
- [ ] 确认 Apple 审核账号 `review@svc.plus` 的技能列表是否需要预配置，或依赖当前的隐藏空状态逻辑即可
- [ ] 确认 `_MobileExecutionTimeline` 删除后是否需要替代方案（当前执行中仅显示 spinner + "正在执行中..."）

---

## 分支策略参考

按照 [project-development-standard.md](file:///Users/shenlan/workspaces/ai-workspace-lab/xworkmate-app/docs/project-development-standard.md) 规范：

- `hotfix/*` 分支 → 目标 `release/v1.1` (PR #126)
- `cherry-pick/*` 分支 → 目标 `main` (PR #127)
- 不直接 push 到 `main` 或 `release/*`，所有变更通过 PR 合并

---

## 本地分支状态

| 分支 | 状态 | 说明 |
|------|------|------|
| `main` | 最新 | 已 pull，含上一轮合并 |
| `release/v1.1` | 最新 | 已 pull |
| `hotfix/mobile-dynamic-artifacts` | 本地 + 远端 | Bug 3 修复，PR #126 |
| `cherry-pick/mobile-dynamic-artifacts` | 本地 + 远端 | Bug 3 cherry-pick 到 main，PR #127 |

---

## 测试账号

| 类型 | URL | 用户名 | 密码 |
|------|-----|--------|------|
| Apple 审核专用只读账号 | https://accounts.svc.plus | `review@svc.plus` | （已从文档移除；该口令曾入库，需按规范第 9 节轮换，轮换后存放于密钥管理处） |

---

## iOS 设备信息

- **设备 UDID / Team ID**: 已从文档移除，见维护者本地记录
- **部署命令**: `flutter run -d <device-udid> --release`
