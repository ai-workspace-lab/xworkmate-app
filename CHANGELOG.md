# Changelog

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
