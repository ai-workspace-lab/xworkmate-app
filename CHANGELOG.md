# Changelog

## 1.2.0 — 2026-08-08

发版分支：`release/v1.2` · Tag：`v1.2.0` · `pubspec.yaml`: `1.2.0+1`

本版是一轮桌面端 UI 交互细节整改，参照 Kun 与 openworker 的交互契约与设计纪律。
详见 [`docs/plans/2026-08-07-ui-interaction-polish-plan.md`](docs/plans/2026-08-07-ui-interaction-polish-plan.md)。

### Highlights

- **三栏零间隙**：面板之间累计 36px 的留白沟被移除。面板不再各自浮成圆角卡片，改为贴合排布、以 1px 发丝线分隔、靠底色分层区分（#243）。
- **输入契约统一**：桌面端 Enter 可发送、Shift+Enter 换行、Cmd/Ctrl+Enter 发送；移动端解除单行限制，可写多行。此前桌面端输入框是多行语义，`onSubmitted` 从不触发，只能点按钮发送（#245）。
- **发送键状态化**：空草稿禁用、运行中显示忙碌态，避免误排第二轮任务。停止仍归进度条，不在组合器重复（#245）。
- **组合器高度联动**：卡片填满所在窗格，不再固守固有高度贴底而在上方留出灰条；组合器内多余的第二个拖动手柄移除，分隔线成为唯一的高度控件（#246）。
- **技能选择器可键盘操作**：↑↓ 移动、Enter 选中、Esc 关闭，搜索框全程保持焦点（#248）。
- **组合器高度持久化**：拖动后的高度写入 UI 状态并在重启后恢复；调整高度时保持会话贴底（#249）。

### Fixes

- 工作台洞察栏在窗口高度低于约 790px 时溢出，现改为滚动（#247）。
- Launchpad PPA 构建环境补 `override_dh_auto_test` 守卫（#244）。

### Design system

- 新增 [`docs/design/pane-layout-pattern.md`](docs/design/pane-layout-pattern.md)：面板与卡片的边界、叠加式分隔线、一个面板只有一个尺寸控件、不得把渲染尺寸回喂给决定该尺寸的值、压缩时从远端降级。含合并前检查表。
- 新增 `AppPaneShell` 与 `AppSpacing.paneContent`：会话页与设置页此前有三套各自硬编码的外框内边距（0 / 24 / 6），现统一为一个令牌。

### Known Issues

- `flutter test` 仍有 6 个既有失败（`mobile_assistant_home_golden_test` 2 个、`mobile_assistant_page_test` 4 个），与本版改动无关，在 `main` 上同样存在。
- `PR Layered Tests` 门禁因上述基线长期为红，实际不提供信号，待单独治理。
- 组合器高度持久化未做端到端验证：现有测试只覆盖 JSON 模型读写，未覆盖「拖动 → 落盘 → 重启读回」链路。

---

> **记录断层说明**：`0.7.0`（2026-03-24）与本版之间的 `1.1.0`–`1.1.10` 共 11 个版本当时未写入本文件。
> 以下条目为 2026-08-08 依据 `pubspec.yaml` 版本变更点与其间的提交历史**事后重建**，
> 仅保留可从 git 核实的要点，不等同于当时的原始发版说明；各版的验证结论与已知问题已无法追溯。
> 生成式的 `docs/releases/xworkmate-changelog.md` 由 `tool/render_release_docs.dart` 从 git 引用渲染，与本文件相互独立。

## 1.1.10 — 2026-07-28

- 制品预览选择范围收敛到工作区内。
- CI：接入 Vault 读取 OBS Token 并自动触发 RPM 构建；接入 Launchpad PPA GPG key 与 dput 发布步骤。
- 工作台保持三栏布局可见。

## 1.1.9 — 2026-07-21

- 移动端抽屉加入语言与主题切换。
- macOS：Runner target 的 deployment target 对齐 Podfile 已强制的 15.6 下限。
- CI：修复导致分支方向门禁失效的非法 permissions 值。

## 1.1.8 — 2026-07-20

- 移动端持久化迁移到 SharedPreferences，清理死代码。
- 修复 iOS 重启后数据被清空的问题。
- 安全：iOS secrets 迁入 Keychain，重装即登出。
- 存储：线程持久化拆分为按会话独立文件。

## 1.1.7 — 2026-07-15

- 移动端附件逻辑补齐。
- 移动端加入紧凑版插件与技能选择器；iOS 任务体验改版。
- 修复 `ListTile` 的 `DecoratedBox` 断言。
- 网关任务提示词中把 Execution 上下文提到 User request 之外。

## 1.1.6 — 2026-07-08

- 制品匹配支持目录级与递归收集。
- 插件工作流状态机第二批：状态迁移、运行追踪、多语言运行时脚手架。
- 组合器按任务会话持久化已选插件。

## 1.1.5 — 2026-06-30

- 以 `pasteboard` 替换 `super_clipboard`，移除 cargokit / Rust 依赖。
- 安装器：断点续传、安全卸载已挂载 DMG、经 API 下载发布产物。

## 1.1.4 — 2026-06-03

- 远程桌面 UI 与客户端 WebRTC 接入。
- Bridge 响应中断后保留制品。
- OpenClaw：制品同步与忽略策略；经 Bridge 控制面重新关联任务。

## 1.1.3 — 2026-05-28

- 修复技能选择器加载。
- 新增任务批量归档。
- 修复 main 分支的 Apple preflight。

## 1.1.2 — 2026-05-24

- 移除移动端审批界面。
- 任务选中顺序保持稳定。
- 网关技能分组显示。

## 1.1.1 — 2026-05-19

- 排队任务反馈可见。
- 支持 OpenClaw 排队任务提交。
- 测试线程工作区相互隔离。

## 1.1.0 — 2026-04-08

- 桌面端 ACP 切换为直连 Go stdio bridge。
- 移除 ACP bypass 兜底路径与过期架构文档。
- 单 Agent 任务流统一到 ACP。
- 网关状态与 ACP endpoint 诊断信息规范化。


## 0.7.0 — 2026-03-24

### Highlights
- 设置页新增 `ACP 外部接入`，支持为 `Codex / OpenCode / Claude / Gemini` 分别配置独立的外部 ACP endpoint。
- Single Agent 外部 ACP 模式不再错误复用本地 LLM API 模型；当前线程会改为显示 ACP 真实返回的运行时模型。
- Codex ACP 直连链路补齐当前协议：`thread/start`/`turn/start` 与新的 `input` item 序列兼容，真实 WebSocket 任务执行已跑通。
- 本地持久化与 macOS 打包链路延续稳定化，`settings.yaml` / `tasks/*.json` / `secrets/*.secret` 的文件存储布局保持不变。

### Current Delivery Scope
- 已交付：外部 ACP endpoint 配置 UI、Codex ACP provider 选择、运行时模型归属修正。
- 已交付：Codex app-server thread/turn 协议适配与 websocket 真实链路验证。
- 已交付：macOS DMG 打包、覆盖安装到 `/Applications/XWorkmate.app` 的发布路径。

### Known Issues
- `flutter test` 全量仍有既有失败：`assistant_page_test` 2 个 pending timer、`modules_page_test` 1 个重复文案断言。
- macOS device-run 仍可能出现 `Failed to foreground app; open returned 1`，需要串行执行并结合人工检查。

### Dev
- `pubspec.yaml`: 当前版本更新为 `0.7.0+1`
- 发版分支：`release/v0.7`
- 预期 tag：`v0.7.0`

## 0.6.1 — 2026-03-22

### Highlights
- 修复本地配置持久化链路：`SecureConfigStore` 增加标准目录 fallback，`SettingsStore`/`SecretStore` 首次启动自动准备耐久目录结构。
- 持久化策略改为默认 fail-fast：当耐久路径不可解析或数据库不可打开时直接报错，避免静默内存化导致重启丢配置。
- 在显式内存回退模式下补齐“尽力回写”机制：后续写入和退出阶段会尝试同步到标准耐久目录。
- 关闭未完备账号入口：`mobile.workspace.account` 与 `desktop.navigation.account` 标记为 `experimental` 且 `enabled: false`。
- 补充回归测试覆盖“路径失败报错”和“默认支持目录 fallback 跨实例持久化”。

### Dev
- `pubspec.yaml`: 当前版本更新为 `0.6.1+1`
- 本次按用户要求直接在 `main` 分支提交，预期 tag 为 `v0.6.1`

## 0.6.0 — 2026-03-22

### Highlights
- 本地配置、Gateway 凭证和 Assistant 任务会话改为以 secure storage 管理的密钥做加密持久化，重启和覆盖安装后不再丢失。
- `单机智能体` 线程补齐本地技能自动发现和当前线程可选技能列表恢复，线程状态与模型选择继续保持隔离。
- Flutter Web assistant shell、Web Chrome 会话持久化和移动端安全控件一起补齐，多端可用性明显提升。
- Assistant composer 高度自适应、执行目标切换即时刷新、侧栏默认宽度等桌面交互问题已收敛。
- Windows / Linux parity、macOS DMG 打包和多平台构建发布流程持续补强。

### Current Delivery Scope
- 已交付：加密后的本地 settings snapshot、assistant threads 和 sealed backup 恢复链路。
- 已交付：Single Agent 线程技能自动发现、线程状态清理和重启恢复。
- 已交付：Flutter Web assistant shell、Web 持久化修复、移动端安全壳控件和桌面布局微调。
- 已交付：Windows / Linux parity 修复、多平台 build and release workflow、macOS 安装与分发产物。

### Not Yet Implemented
- `Settings external agents detail shows Codex bridge runtime states` 相关全量测试基线仍需单独收敛，不纳入本次 release 变更。
- 内置 Codex / Rust FFI 仍保持 experimental，不视为稳定默认运行模式。
- 更通用的外部 Code Agent provider 调度和可视化管理 UI 还未完成。

### Known Issues
- 远程或外部 CLI 协同仍受本机安装状态、Gateway 可达性和环境依赖影响，建议按 case 文档补一轮人工验收。
- macOS integration 测试仍可能受到宿主前台拉起行为影响，需要串行执行并结合人工检查。

### Dev
- `pubspec.yaml`: 当前版本更新为 `0.6.0+1`
- `release/v0.6` 作为本次发版分支，预期 tag 为 `v0.6`

## 0.5.0 — 2026-03-20

### Highlights
- Assistant 任务线程升级为持续会话：支持流式回复、继续追问、线程归档和重启恢复。
- 任务列表按 `单机智能体 / 本地 OpenClaw Gateway / 远程 OpenClaw Gateway` 分组，保持极简列表布局。
- Multi-Agent 协作正式升级为 `Architect / Engineer / Tester`，并可选 `ARIS` 作为最强协作框架。
- ARIS bundle 作为只读资产内嵌进 App，`skills/` 直接复用 upstream，`llm-chat` 与 `claude-review` 切到 Go core。
- `Ollama Cloud` 文案与默认地址统一，Go core 保持为包外开发态能力，不再内嵌进 `.app`。

### Current Delivery Scope
- 已交付：Single Agent streaming threads、OpenClaw 本地/远程任务线程、手动归档与持续会话恢复。
- 已交付：Multi-Agent managed runtime、ARIS framework preset、本地优先 Ollama 回退、Go core runtime 和打包分发。
- 已交付：Settings / Assistant 里的 ARIS 轻量状态展示、任务分组、Ollama Cloud 设置迁移。
- 保持 truth-first：Scheduled Tasks 仍是 `cron.list` 只读视图；Memory 仍是 `memory/sync` 同步能力，不宣传 CRUD。

### Not Yet Implemented
- 内置 Codex / Rust FFI 仍未交付，`builtIn` 只保留为 experimental placeholder，不可视为稳定运行模式。
- 泛化的外部 Code Agent provider chooser / 调度 UI 还未落地；当前以角色配置和 preset 为主。
- OpenClaw Gateway 到外部 CLI 的直连 RPC、无 UI/headless 常驻执行、远程分布式调度不在 `v0.5` 交付范围内。
- `Tasks` 与 `Memory` 相关能力仍以 truth 收口为主，没有新增伪造接口或误导性交互。

### Known Issues
- ARIS local-first 协作仍依赖本地 Ollama endpoint 可达，缺失时会退化到已配置的云端或可用 CLI。
- Gemini / Claude / Codex / OpenCode 的深度能力仍受本机安装状态约束；未安装时只保证回退链路可用。
- 外部 CLI 全链路协作仍建议按 `docs/cases/README.md` 做一轮手动验证。

### Dev
- `pubspec.yaml`: 当前版本为 `0.5.0+1`
- macOS / iOS build name 和 build number 继续由 Flutter 版本号统一驱动
