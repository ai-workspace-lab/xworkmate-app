# 02. Layout、模块分层与状态边界

## 1. 组件层级原则

为保证长期维护，建议严格区分三层：

- Layout 层：只负责结构和容器
- Module 层：负责一个业务单元的交互和状态协调
- Component 层：负责纯展示或轻交互

页面只做组装，不应堆积大量业务逻辑。

## 2. Layout 层

Layout 层应只负责工作区结构，不直接依赖具体业务域。

建议的壳层对象包括：

- WorkspaceShell
- PrimaryRail
- SecondaryPane
- ContentViewport
- TopChromeBar
- BottomDock
- SplitPaneLayout
- SheetHost

这些对象负责：

- 左右分栏
- 顶部导航与 breadcrumb 承载
- 底部 composer 区承载
- 面板折叠与尺寸分配
- Web 响应式适配

## 3. Module 层

Module 是长期维护的关键层，承接复合业务交互。

### A. Assistant 模块

- ThreadListModule
- ThreadGroupsModule
- SessionHeaderModule
- ConversationModule
- RenderModeModule
- ConnectionStatusModule
- ComposerModule
- SessionSettingsSheetModule

### B. Focus / Favorites 模块

- FocusEntriesModule
- FocusSummaryCardModule
- FavoriteEntryManagerModule

### C. Settings 模块

- SettingsTopBarModule
- SettingsSubmissionBarModule
- SettingsTabsModule
- GatewayProfilesModule
- LlmEndpointsModule
- ExternalAcpModule
- AppearanceSettingsModule
- DiagnosticsModule

### D. Resource 模块

- TasksRegistryModule
- SkillsRegistryModule
- NodesRegistryModule
- SecretsRegistryModule
- LlmApiRegistryModule

一个 module 应该负责“完整业务语义”，而不是只拼几个 UI 组件。

## 4. Component 层

Component 层应尽可能保持纯展示和可复用。

建议沉淀为通用组件的对象包括：

- SurfaceCard
- SectionTabs
- SearchField
- StatusChip
- ConnectionBadge
- ActionChip
- EmptyState
- ErrorBanner
- ToolbarButton
- DropdownField
- ToggleField
- SummaryStatChip
- BottomSheetPanel
- ResizeHandle

这些组件不应知道线程、设置页、技能列表等具体业务语义。

## 5. 状态边界

虽然这里主要区分“全局状态”和“局部状态”，但在 Flutter Web 中还应单独重视路由状态。

### A. 全局状态

以下状态建议由 app-level controller / store 持有：

- 当前 workspace / 用户上下文
- 当前主题、语言
- feature flags
- 全局导航结构
- Focus / Favorites 入口列表
- 资源目录数据（任务、技能、节点、密钥、LLM API）
- Gateway profile 列表
- provider / model catalog
- 线程索引数据
- 全局通知 / 错误中心

### B. 路由状态

以下状态更适合映射到 URL / 路由层：

- 当前页面
- 当前线程 id
- 当前 Settings tab
- 当前 Integrations sub-tab
- 当前详情对象 id
- 左侧 pane 当前模式
- 可分享的搜索条件

这些状态如果仅放在内存里，会削弱 Flutter Web 的刷新恢复能力和链接可分享能力。

### C. 局部状态

以下状态建议严格留在模块或组件内部：

- side pane 折叠/展开
- split pane 临时尺寸
- bottom sheet 是否打开
- dropdown 是否展开
- 输入框内容
- 当前附件选择结果
- 卡片折叠状态
- 某个按钮 loading
- 某个 form 的未提交草稿
- hover / pressed / focused 视觉状态
- 局部滚动位置

## 6. 一条可执行的状态规则

建议全团队统一以下判断标准：

- 会影响多个页面或多个模块的，进入全局状态
- 需要刷新恢复或支持深链的，进入路由状态
- 只影响单个模块交互的，保持局部状态

## 7. 必须统一复用的状态机

长期维护时，最容易失控的不是 UI 样式，而是行为流。

建议优先统一以下状态机：

- Test / Save / Apply
- Connect / Connected / Error / Retry
- Thread Send / Streaming / Cancel / Complete
- Load / Empty / Error / Refresh
- Select / Attach / Remove / Oversize
- Collapse / Expand / Pin / Unpin

这些状态机一旦被各页面各写一套，后续 Assistant、Settings、Focus、资源域的交互会快速分叉。
