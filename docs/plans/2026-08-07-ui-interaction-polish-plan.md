# XWorkmate UI 交互细节微调规划

- 日期：2026-08-07
- 参照项目：`~/workspaces/Kun`（Electron + React 19 + Tailwind）、`~/workspaces/openworker`（Tauri + React，`surfaces/gui`）
- 目标仓库：`xworkmate-app`（Flutter，desktop + mobile 双形态）
- 性质：交互细节微调，不改信息架构、不改导航骨架、不引入新框架

---

## 0. 方法与边界

本规划只借鉴两个参照项目的**交互契约与设计纪律**，不搬运其实现形态：

- Kun 的价值在于 **`DESIGN.md` 这套「机器可读令牌 + 编辑性说明 + 合并前检查表 + 反模式清单」的治理方式**，以及明确的动效/圆角/阴影阶梯。
- openworker 的价值在于 **每个非显然的 UI 决策都在代码里写清了理由、日期和规范条款号**，以及一批具体的组合器（composer）交互约定。
- 两者都是 Web 技术栈，其 CSS/DOM 实现（`<details>`、`aria-*`、Tailwind 类名）**不可直接移植**；可移植的是行为语义，Flutter 侧用 `ExpansionTile`/`Semantics`/`Shortcuts` 等价实现。

不在本规划范围内：换主题体系、换配色、重做工作台（Workbench）信息架构、引入第二套组件库。

---

## 1. 三方交互契约对照

| 维度 | Kun | openworker | XWorkmate 现状 |
|---|---|---|---|
| 回车发送 | Enter 发送 / Shift+Enter 换行 / Ctrl+Enter 发送 | Enter 发送 / Shift+Enter 换行 | **桌面端无效**（见 2.1）；移动端有 |
| 多行输入 | 有 | 有 | 桌面有；**移动端锁死单行** |
| 中断运行 | 有（`Square`/`PauseCircle`） | 有（`onInterrupt` + Esc） | **无** |
| 发送键状态机 | 空/可发/运行中 三态 | 同上，且未配模型时改走 setup 并保留草稿 | **恒可点，单态** |
| 弹层键盘导航 | 有（斜杠菜单、模型选择器） | 有（↑↓ 选择、Enter 确认、Esc 关闭） | **无** |
| 圆角阶梯 | 4→28 共 11 级，按角色映射 | — | **全部 12，仅一级** |
| 间距阶梯 | 4px 基数，13 级 | — | `sm`=`md`=`lg`=8，**三级同值** |
| 动效令牌 | micro 140 / standard 150 / deep 300 + 用途说明 | — | 140/160/180/200/220/240/250… 散落 |
| 循环动效 | 仅 2 个（liveness pulse、streaming shimmer） | 流式行 pulse | 无统一约定 |
| 空态起手式 | `ChatStarterGrid` 三张卡，点击预填组合器 | `SessionIntro` 三条模板任务 + 连接点状态 | **仅一张连接状态卡 + 一个按钮** |
| 工具调用/审批 | 折叠 | **默认折叠**，展开是 opt-in | 未成体系 |
| 选择器项描述 | 有 | 有（Discuss / Ask for approval / Full access + 说明） | **裸 id / 裸标签** |
| 设计权威文档 | `DESIGN.md`（单一权威 + 检查表 + 反模式） | 代码内决策注释（含日期与条款号） | `design-qa.md`（单次 issue 的验收记录） |

---

## 2. 已确认的具体问题（含证据）

### 2.0 三栏之间有 26px 的「留白沟」，每块面板还各自浮成卡片 — P0（最显眼）

这是截图里第一眼就能看出来的问题。当前**用「留白 + 圆角 + 描边」做面板区隔**，而参照的 OpenWorker 是**用 1px 分隔线 + 底色差**做区隔，栏间零间隙。

**横向间隙逐项核账**（从窗口左边缘算起）：

| 位置 | 值 | 出处 |
|---|---|---|
| 窗口 → 左栏 | 4px 外边距 | `sidebar_navigation.dart:103` `margin: fromLTRB(4,4,4,0)` |
| 左栏 → 分隔 | 4px 外边距 | 同上（右侧） |
| 分隔本身 | **8px** | `app_shell_desktop.dart:405` `PaneResizeHandle(extent: 8)` |
| 中栏内：任务栏 ↔ 会话 | 6 + 2 = **8px** | `assistant_page_main.dart:42,43` `…ResizeHandleWidth = 6` + `…PaneGap = 2` |
| 中栏内：会话 ↔ 制品栏 | 6 + 2 = **8px** | `assistant_page_state_closure.dart:336,353` |
| 中栏 → 窗口右缘 | 4px | `app_shell_desktop.dart:418` `Padding fromLTRB(0,4,4,0)` |

合计 36px 的沟。（实施时发现内部边界各是两个常量叠加，比初测的 6px 多一个 2px 的 `assistantHorizontalPaneGapInternal`。）再叠加两层「卡片化」：

- 每个面板自己是圆角卡片——`desktop_workspace_scaffold.dart:107-117` 给中栏套了 `borderRadius: AppRadius.card`(12) + `Border.all(strokeSoft)`；`sidebar_navigation.dart:103` 同理。
- 分隔线不是线，是**一截 2×42 的胶囊**——`pane_resize_handle.dart:52-53` 只在中点画 42px 高的小条，其余全是空白。所以栏与栏之间看起来是「断开的」，不是「相邻的」。

对照图2（OpenWorker）：左/中/右直接贴合窗口边缘与彼此，**通栏 1px 分隔线**，面板无圆角、无外边距；区隔靠底色分层（左栏浅灰、中栏白、右栏浅灰）。

### 2.0.1 设置页与会话页不共用外框节奏 — P0

- 会话页走 `DesktopWorkspaceScaffold(padding: EdgeInsets.zero)`（`assistant_page_main.dart:200`），把内边距完全交给内部。
- 设置页走另一套 `SettingsPageBodyShell`（`settings_page_shell.dart`），TopBar 后固定 `SizedBox(height: 24)`（`:57`）、applyBar 后 16（`:60`），外加自己的 `padding` 入参。
- 而 `DesktopWorkspaceScaffold` 的**默认** padding 又是 `fromLTRB(6,6,6,0)`（`:16`），第三套值。

三套并存 → 图1 与图3 的留白节奏对不上。这就是「页面还不统一」的根因：**没有一个统一的面板容器**，每个页面各自决定外框。

### 2.1 桌面端「回车发送」实际不生效 — P0

`lib/features/assistant/assistant_page_composer_bar.dart:607,609,623`

```dart
expands: true,
maxLines: null,
onSubmitted: (_) => handleSendInternal(),
```

Flutter 中 `maxLines: null` 会把输入框切为多行语义，Enter 插入换行，`onSubmitted` **不会触发**。因此桌面端唯一的发送路径是点击按钮（`:772`）。这条 `onSubmitted` 是失效代码，容易让人误以为快捷键已实现。

### 2.2 移动端无法多行输入 — P0

`lib/features/mobile/mobile_assistant_page_composer.dart:516`：`maxLines: 1`。

与桌面端形成反向割裂：**桌面能多行不能回车发送，移动能回车发送不能多行**。同一产品的两个形态，输入契约相反。

### 2.3 发送按钮无状态机 — P0

`assistant_page_composer_bar.dart:400,772`：`submitLabel` 恒为「提交」，`onPressed: handleSendInternal` 无条件绑定。缺两件事：

- 输入为空时的 disabled 态；
- 运行中的 busy 态。

**更正（2026-08-07 实施时发现）**：本节初稿曾断言「没有任何用户可点的中断控件」，**该结论是错的**。`assistant_task_progress_bar.dart:109-118` 有一个带文字的「停止」按钮，在 `state.running` 时显示，接在 `assistant_page_state_closure.dart:182` 的 `controller.abortRun()` 上，旁边还有 `recoverable` 态的「继续」。初稿检索 `interrupt`/`停止` 时漏了 `onStop`/`abortRun`。

因此**不要**在组合器里再放一个停止按钮——那会让「运行中能否停止」这一事实有两个来源，正是本规划引用 openworker 时推崇的反面。组合器只需在运行中把发送键置为 busy，停止仍归进度条。

### 2.3.1 组合器高度有两个互不相通的控件 — P0（用户实测报告，2026-08-07）

拖动下窗格的分隔线把窗格拉高后，组合器卡片**保持原有高度并贴底**，上方留出一大片灰色死区。

三层原因叠加：

1. `assistant_page_main.dart` 的 `AssistantLowerPaneInternal` 用 `OverflowBox(minHeight: 0, maxHeight: infinity, alignment: bottomCenter)` 包住组合器——组合器按**固有高度**渲染并贴底，外层 `ClipRect` 负责裁切。窗格变高时它不会跟着长。
2. `assistant_page_composer_bar.dart` 的卡片 `Column` 是 `MainAxisSize.min` + `MainAxisAlignment.end`，输入区是**固定** `SizedBox(height: inputHeightInternal)`。
3. 存在**第二个**高度控件 `ComposerResizeHandleInternal`，只改 `inputHeightInternal`，与窗格分隔线各管各的。

**注意两个坑**（实施时踩到）：

- 直接让卡片填满会形成**反馈环**：`reportContentHeightInternal` 把测得高度回喂给 `composerMeasuredContentHeightInternal` → `defaultComposerHeight` → 窗格高度 → 测得高度……每帧增长。必须改成**计算**最小高度，不再回喂测量值。
- `OverflowBox` 不是冗余的：`assistant_lower_pane_test.dart` 有一条用例在 112px 窗格下断言**提交按钮仍可见**。它靠的正是「固有高度 + 贴底 + 从顶部裁切」。改成填满后这条会挂。正确解法是给组合器一个**紧约束**高度 `max(窗格高, 组合器最小高)`：够高就填满，不够就按最小高贴底、从顶部裁掉工具栏——提交行永远是最后被牺牲的。

### 2.4 键盘可达性近乎为零 — P0

全仓 `Shortcuts`/`LogicalKeyboardKey` 绑定只有组合器里的 `Cmd/Ctrl+V` 粘贴（`:96-98`）。技能选择器是 `OverlayPortal` 弹层（`:190+`），**无 ↑↓ 选择、无 Enter 确认、无 Esc 关闭**，只能用鼠标。

### 2.5 设计令牌阶梯坍塌 — P1

`lib/theme/app_theme.dart:24`（`SimpleSpacing`）：`sm`、`md`、`lg` **全部等于 8**；`page` 为 0。
`lib/theme/app_theme.dart:38`（`SimpleRadius`）：`card`/`button`/`input`/`chip`/`badge`/`dialog`/`sidebar`/`icon` **全部等于 12**。

令牌名还在，语义已消失。结果是**形状和间距无法承担层次表达**——徽章、按钮、卡片、对话框在视觉上同级。对照 Kun：chip 用 pill、card 12、dialog 22、composer 28，形状本身即层级。

### 2.6 StatusBadge 三种语义态背景同色 — P1

`lib/widgets/status_badge.dart:17-22`：

```dart
StatusTone.success => (palette.surfacePrimary, palette.success),
StatusTone.warning => (palette.surfacePrimary, palette.warning),
StatusTone.danger  => (palette.surfacePrimary, palette.danger),
```

三种态的背景都是 `surfacePrimary`，**与其所在卡片底色相同**，徽章的「块感」消失，只剩文字颜色差异。而 `neutral`/`accent` 却有独立底色，同一组件内两套规则。

### 2.7 SectionTabs 双层 chrome 嵌套 — P1

`lib/widgets/section_tabs.dart:36-50` 容器有渐变 + 描边 + `chromeShadowAmbient`；`:101-127` 每个 chip **又**有渐变 + 描边 + `chromeShadowLift`。阴影套阴影、渐变套渐变，选中态的信噪比被削弱。

### 2.8 空态没有起手式 — P1

`lib/features/assistant/assistant_page_components.dart:523`（`AssistantEmptyStateInternal`）：一张卡，内容是**连接状态**，动作是单个按钮（开始输入 / 重连 / 连接）。用户在这里得到的是「系统状态」，不是「我可以做什么」。

对照 openworker `SessionIntro` 的明确纪律：*副标题永远写任务的产出（outcome），不写连接状态*；连接状态用小圆点表示（品牌色=已连通，灰=未连通）。

### 2.9 选择器缺描述、缺加载态 — P1

组合器的模型选择器（`:540+`）直接把 `modelOptions` 的裸字符串铺进 `PopupMenuItem`；权限选择器（`:690+`）同理。没有分组、没有说明、没有「加载中」占位。

对照 openworker 的两条约定：
- 权限项带人话标签与说明：`Discuss` / `Ask for approval` / `Full access`；
- **绝不硬编码兜底模型列表**，服务端未返回时渲染一个 disabled 的「Loading models…」chip（其注释记录了 2026-07-21 因为兜底列表过期而暴露了后端从未确认的 id）。

### 2.10 动效未令牌化 — P2

全仓时长分布：`160`×8、`180`×5、`220`×4、`200`×4、`140`×3、`250`、`240`、`120`、`50`、`500`×2、`1200`。曲线 `easeOutCubic`×12、`easeInCubic`×2、`easeInOut`×1。相近时长各自为政，无「什么场景用哪一档」的约定。

---

## 3. 分批改造计划

### 第零批 P0：零间隙三栏 + 统一面板容器（约 1 天）

目标形态（对齐图2）：**面板贴合，1px 分隔，底色分层，圆角只属于内容卡片、不属于面板**。

| # | 改动 | 落点 |
|---|---|---|
| 0.1 | `PaneResizeHandle` 改为「视觉 1px、命中 8px」：可见部分是**通栏** 1px 线（`strokeSoft`），拖拽命中区用 `OverflowBox` 撑到 8px 但**不占布局宽度**；hover/drag 时整条线转 `accent`，去掉 2×42 胶囊 | `pane_resize_handle.dart:30,46-61` |
| 0.2 | 三处栏间宽度归零：`extent: 8` → `1`；`assistantHorizontalResizeHandleWidthInternal` 6 → `1`（两处引用同一常量） | `app_shell_desktop.dart:405`、`assistant_page_main.dart:42`、`assistant_page_state_closure.dart:337` |
| 0.3 | 去掉面板外边距：侧栏 `margin: fromLTRB(4,4,4,0)` → `EdgeInsets.zero`；中栏 `Padding fromLTRB(0,4,4,0)` → 去掉 | `sidebar_navigation.dart:103`、`app_shell_desktop.dart:418` |
| 0.4 | 面板去卡片化：`DesktopWorkspaceScaffold` 的 `DecoratedBox` 去掉 `borderRadius` 与四边 `Border.all`，改为底色 + 需要处单边 1px；默认 padding `fromLTRB(6,6,6,0)` → `EdgeInsets.zero` | `desktop_workspace_scaffold.dart:16,107-117` |
| 0.5 | 底色分层承担区隔：左栏 `palette.sidebar`、中栏 `palette.surfacePrimary`、右栏 `palette.chromeBackground`；分隔线统一 `palette.strokeSoft` | 上述各面板容器 |
| 0.6 | 抽出统一面板容器 `AppPaneShell`（背景 + 可选单边分隔 + 统一内容内边距 `AppSpacing.paneContent`），**会话页与设置页都改走它**；`SettingsPageBodyShell` 的 24/16 硬编码换成令牌 | `lib/widgets/app_pane_shell.dart`（新）、`settings_page_shell.dart:57,60` |
| 0.7 | 明确规则并写进文档：**圆角与描边只属于内容卡片（`SurfaceCard`），不属于面板**。否则去掉面板圆角后会被逐处补回来 | §3.6 的 `DESIGN.md` |

**验收**：三栏在窗口最大化/最小宽度下均无可见留白沟；分隔线通栏且可拖拽（命中区仍 ≥8px）；会话页与设置页的内容内边距取同一个令牌。
**注意**：0.1 的「命中区大于视觉宽度」是本批唯一有技术含量的点——Flutter 里用 `SizedBox(width: 1)` 包 `OverflowBox(maxWidth: 8)` + `HitTestBehavior.translucent`，不要靠加宽 `SizedBox` 实现，那样沟就又回来了。

### 第一批 P0：输入与控制契约（约 1–1.5 天）

统一「桌面/移动」输入契约，补齐运行控制。这批不动任何视觉。

| # | 改动 | 落点 |
|---|---|---|
| 1.1 | 桌面组合器接入 `Shortcuts`/`Actions`：Enter 发送、Shift+Enter 换行、Cmd/Ctrl+Enter 发送；删除失效的 `onSubmitted` | `assistant_page_composer_bar.dart:591-625` |
| 1.2 | 移动组合器改 `minLines: 1, maxLines: 5`，`textInputAction` 保持 `send`，Shift+Enter 换行 | `mobile_assistant_page_composer.dart:514-518` |
| 1.3 | 发送按钮三态：空输入 disabled、运行中 busy（不重复放停止，见 2.3 更正）、其余可发 | `assistant_page_composer_bar.dart:400,769-792` |
| 1.4 | Esc 走**已有的** `controller.abortRun()` 通路（进度条已在用），不新增 controller API | 组合器 + `app_shell_desktop.dart` |
| 1.5 | 技能选择器弹层键盘导航：↑↓ 移动高亮、Enter 选中、Esc 关闭、Tab 循环 | `assistant_page_composer_skill_picker.dart` |
| 1.6 | 全局 Esc 契约：优先关最上层弹层 → 其次收起技能选择器 → 最后中断运行 | `app_shell_desktop.dart` |

**验收**：新增 widget 测试覆盖 Enter/Shift+Enter/Esc/停止四条路径；桌面与移动各跑一遍发送。
**注意**：`test/features/desktop/desktop_input_handler_test.dart` 已有键盘测试可作模板；`docs/xworkmate-app-core-functional-test-plan-v1.md` 中的发送用例需同步更新。

### 第二批 P1：视觉层次与反馈（约 2 天）

| # | 改动 | 落点 |
|---|---|---|
| 2.1 | 恢复圆角阶梯：`badge` 999（pill）、`chip` 999、`button` 8、`input` 10、`card` 12、`sidebar` 12、`dialog` 20、`icon` 8。保留 `SimpleRadius` 类名以免大面积改调用点 | `app_theme.dart:38` |
| 2.2 | 恢复间距阶梯：`xxs` 4、`xs` 6、`sm` 8、`md` 12、`lg` 16、`xl` 24、`page` 16。**逐屏回归**，这是本批风险最高项 | `app_theme.dart:24` |
| 2.3 | `StatusBadge` 三语义态给独立柔和底色（accent 已有 `accentMuted`，为 success/warning/danger 补 `*Muted`），并去掉徽章上多余的 `boxShadow` | `app_palette.dart` + `status_badge.dart:17-38` |
| 2.4 | `SectionTabs` 去掉一层 chrome：容器保留描边 + 底色，chip 只在选中态给 `chromeShadowLift`，hover 只改底色不加阴影 | `section_tabs.dart:36-50,101-127` |
| 2.5 | 空态改为「起手式」：保留连接状态为**一行细状态条**，主体换成 3 张任务模板卡，点击预填组合器（对照 Kun `ChatStarterGrid` + openworker `SessionIntro`）；副标题写产出不写连接状态 | `assistant_page_components.dart:523` |
| 2.6 | 模型/权限选择器：项内加副标题说明；模型列表未就绪时渲染 disabled「加载模型中…」项，**不做硬编码兜底** | `assistant_page_composer_bar.dart:540-570,690+` |
| 2.7 | 附件按 `name + size` 去重，上限 8 张，超限给 SnackBar 提示 | `assistant_page_composer_bar.dart:570-585` |

**验收**：2.1/2.2 需跑一遍 golden/响应式回归（`design-qa.md` 记录过移动端行溢出，改间距务必复测窄宽度）。

### 第三批 P2：体系化与治理（约 1.5 天）

| # | 改动 | 落点 |
|---|---|---|
| 3.1 | 新增 `AppMotion` 令牌：`micro` 140（hover/焦点环）、`standard` 180（卡片、面板）、`deep` 280（对话框、路由）、`pulse` 1800（liveness）。把现有 160/200/220/240/250 归档到三档 | `lib/theme/app_motion.dart`（新） |
| 3.2 | 循环动效收敛为两个：任务运行中的状态点 pulse、流式文本 shimmer。其余禁止循环 | `assistant_task_progress_bar.dart` 等 |
| 3.3 | 焦点环契约：所有可点元素 `focus-visible` 时 1px accent@30% 环；最小命中区 32px（移动 44px） | `app_theme.dart` 全局 `focusColor` + 各控件 |
| 3.4 | 工具调用/审批默认折叠，展开为 opt-in；折叠标题在流式期间显示 pulse 的活动行 | `assistant_page_message_widgets.dart` |
| 3.5 | 补 `Semantics` 标签：当前 `Tooltip` 仅约 28 处，图标按钮大量无可访问名 | 各 `widgets/` |
| 3.6 | 建立 `docs/design/DESIGN.md` 作为单一权威：令牌表 + 布局语法 + 键盘契约 + **合并前检查表** + **反模式清单**（对照 Kun `DESIGN.md` §3.12 与 §15） | `docs/design/DESIGN.md`（新） |

---

## 4. 借鉴清单：明确「学什么」与「不学什么」

**学 Kun：**
- 单一权威设计文档 + 机器可读令牌 + 合并前检查表 + 反模式清单（3.6）
- 圆角/间距/阴影按角色分级，形状承担层次（2.1、2.2）
- 动效分档 + 「什么场景用哪一档」，循环动效只留两个（3.1、3.2）
- 空态给起手式而非状态播报（2.5）

**学 openworker：**
- 非显然的 UI 决策在代码注释里写清**理由 + 日期**（贯穿全部改动）
- 选择器项带人话说明；不硬编码兜底列表，未就绪就显式 disabled（2.6）
- 键盘优先的弹层：↑↓/Enter/Esc（1.5）
- 运行中可中断，Esc 即取消（1.4、1.6）
- 附件去重 + 上限（2.7）
- 默认折叠工具调用，展开 opt-in（3.4）
- 「同一事实只有一个来源」——同一状态在两个界面必须读同一份数据，不允许两处各算一次

**不学：**
- 不搬 Kun 的三栏 + 右侧 inspector 布局语法（XWorkmate 的工作台信息架构已在 issue #213 验收过，见 `design-qa.md`）
- 不搬 Web 特有实现（`<details>`、`aria-*`、Tailwind 类名）——Flutter 用 `ExpansionTile`/`Semantics` 等价实现
- 不引入第二套主题体系；`AppPalette` 已是 `ThemeExtension`，扩展它即可
- 不做 Kun 的 pill 形窗口 chrome / 玻璃拟态；XWorkmate 已有自己的 chrome 令牌
- openworker 的 persona/connector 体系与 XWorkmate 的插件-连接器模型不同，只借交互形态不借概念

---

## 5. 风险

1. **2.2 间距阶梯恢复是本规划风险最高项**。`sm/md/lg` 从统一 8 拆成 8/12/16，所有用到 `AppSpacing.md`、`.lg` 的地方间距都会变大。必须逐屏回归，尤其复测窄宽度溢出（`design-qa.md` 第 41 条记录过这类回归）。建议单独一个 PR，不与其他改动混。
2. **1.3 停止按钮依赖后端中断能力**。需先确认 bridge / OpenClaw runtime 是否支持中途取消；若不支持，第一批先只做「空输入 disabled + 运行中 busy」两态，停止按钮延后到后端就绪。
3. 2.5 空态改造涉及新文案，需 zh/en 双语同时落地（仓库现有 `appText(zh, en)` 模式）。

---

## 6. 建议的推进顺序

第零批（零间隙三栏，独立 PR，视觉收益最大）→ 第一批（P0 输入契约，独立 PR）→ 2.3/2.4/2.6/2.7（低风险视觉，可合并为一个 PR）→ 2.1（圆角，独立 PR）→ 2.2（间距，独立 PR + 完整回归）→ 第三批（P2，可拆多个小 PR，3.6 文档先行）。

第零批与 2.1（圆角阶梯）有交叉：0.4 去掉的是**面板**圆角，2.1 调整的是**内容卡片**圆角，两者不冲突，但 0.7 的规则必须先立，否则 2.1 会把圆角又加回面板上。

分支与 PR 目标遵循 `docs/project-development-standard.md`。
