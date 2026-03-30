# 03. Flutter Web 目录设计与复用策略

## 1. 目录设计目标

Flutter Web 目录设计需要同时解决四个问题：

- 让 Workspace Shell、Assistant、Settings、资源域边界清晰
- 让 Web 平台适配逻辑与业务逻辑分离
- 让模块和状态机能够跨页面复用
- 让未来继续补齐桌面能力时，不需要大规模迁移目录

因此，建议采用：

- app：应用壳与全局入口
- core：通用基础能力
- platform/web：浏览器平台适配
- features：按业务域拆分
- shared：跨 feature 的复合复用模块

## 2. 建议目录结构

### A. app

负责应用级内容：

- bootstrap
- app shell
- navigation
- routing
- theme
- localization
- global app state

### B. core

只放通用、稳定、与具体业务域无关的能力：

- design system
- primitives
- async/result models
- shared service contracts
- common value objects
- utility helpers

### C. platform/web

专门承接 Web 平台相关实现：

- browser storage
- file picker
- clipboard
- drag resize
- window metrics
- url sync
- web socket / SSE adapters

这样可以避免在 feature 目录里到处散落浏览器特例逻辑。

### D. features

按业务域拆分，每个域内部再分层：

- presentation
- application
- domain
- data

建议至少建立以下 feature：

- assistant
- focus_entries
- tasks
- skills
- nodes
- secrets
- llm_endpoints
- settings

### E. shared

用于放跨 feature 的复合件，而不是基础原子组件：

- shell_modules
- status_widgets
- form_patterns
- summary_cards
- registry_helpers

## 3. 每个 feature 的分层建议

以 feature-first 为原则，每个 feature 保持四层：

### presentation

负责页面、布局组装、模块展示：

- pages
- layouts
- modules
- components

### application

负责交互编排与状态协调：

- controllers / coordinators
- use cases
- screen state
- action handlers

### domain

负责业务模型与规则：

- entities
- value objects
- policies
- domain services

### data

负责数据读写与适配：

- repositories
- dto
- mappers
- remote/local data source

## 4. 组件复用策略

建议把复用拆成四层，而不是只做视觉组件复用。

### A. 视觉原子复用

用于保证视觉和交互基础一致：

- Button
- Card
- Tabs
- Input
- Badge / Chip
- Empty / Error / Loading state
- BottomSheet
- SplitHandle

### B. Shell 结构复用

用于保证工作台结构一致：

- WorkspaceShell
- TopChromeBar
- PrimaryRail
- SecondaryPane
- BottomDock
- ResizablePaneLayout

### C. 业务模块复用

用于复用完整交互语义：

- ThreadListModule
- FocusSummaryCardModule
- SettingsSubmissionBarModule
- ConnectionProfileModule
- EndpointEditorModule
- ResourceListDetailModule

### D. 状态机复用

用于复用行为，而不是只复用 UI：

- Save / Apply flow
- Connection test flow
- Streaming lifecycle
- Attachment lifecycle
- Search / filter / selection flow

## 5. 注册表驱动策略

结合截图中的“关注入口”、左侧导航和资源域，建议采用注册表驱动策略。

每个业务域应向系统注册自己的：

- id
- label
- icon
- page destination
- summary preview builder
- favorite capability
- feature flag 依赖
- permission / availability 条件

这样可以解决几个长期问题：

- 新增域时不需要修改多个壳层文件
- Focus Entries 可以自动枚举可收藏域
- Web / Desktop / Mobile 可以共享同一套产品语义，只做平台级裁剪

## 6. 维护约束建议

为了防止目录逐步失控，建议团队明确以下约束：

- page 只做路由承接和模块组装，不写复杂业务逻辑
- module 可以依赖 component，但 component 不反向依赖 module
- feature 不直接依赖其他 feature 的 presentation 层
- Web 平台适配逻辑不进入 core
- Save / Apply、线程会话、连接状态等关键状态流统一复用，不允许每页自定义一套

## 7. 结论

如果以当前 macOS APP UI 作为基准，Flutter Web 的目标不应是“单独实现一个简化网页”，而应是：

- 共享同一套 Workspace 产品语义
- 在 Web 中复用相同的 Shell、页面域、模块边界和状态机
- 只在平台能力、导航密度和交互载体上做 Web 裁剪

这将使 Web 版本具备持续演进能力，而不是停留在一次性补齐页面的实现方式。
