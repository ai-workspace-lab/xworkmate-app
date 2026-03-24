# 01. Information Architecture 与页面结构

## 1. 顶层信息架构

以当前 macOS APP UI 为基准，XWorkmate 应被理解为一个 AI Workspace / Agent Operating System，而不是一个普通聊天应用。

建议把整体信息架构划分为四层：

### A. Workspace Shell

负责整个应用的结构外壳：

- 顶层导航
- 页面切换
- 左侧栏与工作区布局
- 全局搜索入口
- 主题、语言、全局反馈
- Focus / Favorites 入口容器

这一层不承载具体业务逻辑，只负责承载各域页面与全局交互容器。

### B. Execution Plane

这是用户最常驻的工作平面，核心是 Assistant：

- 任务线程
- 对话上下文
- Agent 运行状态
- 渲染结果
- 会话级执行参数
- 底部 composer 与运行入口

这一层的核心对象不是单条 message，而是 thread / task session。

### C. Resource Plane

这是任务执行依赖的能力资产层：

- 任务
- 技能
- 节点
- 密钥
- LLM API

这些对象本质上是资源目录，不应被挤压进 Assistant 页面内部逻辑。

### D. Control Plane

负责系统与环境配置：

- Settings
- Gateway / External ACP / LLM endpoint 配置
- 权限级别
- 主题、语言
- Diagnostics / About

该层的目标是集中管理系统配置，而不是在多个页面散布零碎设置按钮。

## 2. 关键对象与关系

### A. Thread 是一级工作对象

每个线程都应具备独立的：

- 标题
- 执行目标（single / local / remote）
- provider / model / permission / skills
- 连接状态
- 归档状态
- 消息历史与渲染结果

因此，线程列表不是 message history 的附属视图，而是工作台的一级对象目录。

### B. Focus Entry 是聚合入口，不是独立业务域

“关注入口”不应被视为与任务、技能、节点并列的业务模块。

它的职责应该是：

- 收藏某个业务域入口
- 给出摘要预览
- 提供快速跳转
- 在 Assistant 工作区左侧提供上下文补充

它属于导航聚合层，不属于核心资源域。

### C. Settings 是控制中心，不是弹窗集合

连接设置、语言、主题、权限、执行目标默认项等，不应在多个页面各有一份完整编辑面板。

建议规则：

- 页面内只保留会话级快捷调整
- 系统级配置统一回到 Settings
- 所有连接相关能力遵循统一的 Test / Save / Apply 语义

## 3. 页面划分

### A. 主页面

建议以稳定业务域来划分主页面，而不是按截图中的单个按钮来划分：

- Assistant Workspace
- Tasks
- Skills
- Nodes
- Secrets
- LLM API
- Settings

### B. 详情页面

资源域应支持详情态，以便长期扩展：

- Task Detail
- Skill Detail
- Node Detail
- Secret Detail
- LLM Endpoint Detail
- Assistant Thread Detail

详情页面可以是独立页面，也可以在桌面大屏下表现为右侧 detail panel，但产品语义上仍应视为详情态。

### C. 面板式子视图

以下内容更适合做 side pane / sheet / overlay，而不应都变成独立主页面：

- Focus Entries
- 会话设置底部弹层
- 附件选择
- 错误详情
- 渲染模式切换
- 线程搜索结果
- 快捷摘要卡

## 4. Assistant 页面结构

Assistant 不是单页聊天窗口，而是一个复合工作台：

- 左侧：线程栏
- 左侧辅助：Focus / Favorites 面板
- 中间：当前线程主内容
- 顶部：会话头与状态栏
- 底部：composer dock
- 底部弹层：会话级设置

因此，Assistant 的信息架构应被定义为“工作台容器 + 多模块协作”，而不是单个 page widget。

## 5. Settings 页面结构

以桌面基准来看，Settings 应明确是控制平面页面，建议稳定为：

- Top bar（breadcrumb / title / search）
- Submission bar（Save / Apply）
- Primary tabs（General / Workspace / Integrations / Appearance / Diagnostics / About）
- Integrations sub-tabs（OpenClaw Gateway / LLM Endpoints / External ACP）
- Detail sections / cards

这能保证 Web 与 macOS APP 在信息层级上保持一致，即使具体交互密度有所裁剪。
