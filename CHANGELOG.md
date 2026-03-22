# Changelog

## 0.6.0 — 2026-03-22

### Highlights
- 本地配置、Gateway 凭证和 Assistant 任务会话改为以 secure storage 管理的密钥做加密持久化，重启和覆盖安装后不再丢失。
- `仅 AI Gateway` 线程补齐本地技能自动发现和当前线程可选技能列表恢复，线程状态与模型选择继续保持隔离。
- Flutter Web assistant shell、Web Chrome 会话持久化和移动端安全控件一起补齐，多端可用性明显提升。
- Assistant composer 高度自适应、执行目标切换即时刷新、侧栏默认宽度等桌面交互问题已收敛。
- Windows / Linux parity、macOS DMG 打包和多平台构建发布流程持续补强。

### Current Delivery Scope
- 已交付：加密后的本地 settings snapshot、assistant threads 和 sealed backup 恢复链路。
- 已交付：Gateway-only 线程技能自动发现、线程状态清理和重启恢复。
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
- 任务列表按 `仅 AI Gateway / 本地 OpenClaw Gateway / 远程 OpenClaw Gateway` 分组，保持极简列表布局。
- Multi-Agent 协作正式升级为 `Architect / Engineer / Tester`，并可选 `ARIS` 作为最强协作框架。
- ARIS bundle 作为只读资产内嵌进 App，`skills/` 直接复用 upstream，`llm-chat` 与 `claude-review` 切到 Go bridge。
- `Ollama Cloud` 文案与默认地址统一，打包后的 `.app` 会随同分发 `xworkmate-aris-bridge` helper。

### Current Delivery Scope
- 已交付：AI Gateway-only streaming threads、OpenClaw 本地/远程任务线程、手动归档与持续会话恢复。
- 已交付：Multi-Agent managed runtime、ARIS framework preset、本地优先 Ollama 回退、Go bridge runtime 和打包分发。
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
