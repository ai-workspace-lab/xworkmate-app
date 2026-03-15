# Changelog

## 0.4.0 — 2026-03-15

### Highlights
- Assistant 现在作为默认主页，首页围绕“默认任务”工作台展开。
- 左侧统一侧板收敛为固定 `任务 / 导航` 加自定义关注入口，支持折叠、拖拽和更宽的动态调整。
- 任务列表与当前对话打通，当前会话默认作为任务上下文持续保留，只有归档后才从列表移除。
- Breadcrumb、关注入口预览和默认主页面路由已经统一到 assistant 工作台。
- Codex 集成路线明确为 external-first：当前可交付路径是外部 Codex CLI，经由 XWorkmate 作为 app-mediated cooperative node 与 OpenClaw Gateway 协同。

### Current Delivery Scope
- 已交付：外部 Codex CLI bridge、AI Gateway 模型桥接、OpenClaw Gateway 协同注册、assistant 工作台与任务侧栏、macOS DMG 打包链路。
- 已交付：关注入口收藏、左侧侧板动态宽度、面包屑导航、任务列表保留与归档流转。
- 保持 truth-first：Scheduled Tasks 仍是 `cron.list` 只读视图；Memory 仍是 `memory/sync` 同步能力，不宣传 CRUD。

### Not Yet Implemented
- 内置 Codex / Rust FFI 仍未交付，`builtIn` 只保留为 experimental placeholder，不可视为稳定运行模式。
- 其他外部 Code Agent CLI 的统一 chooser / 调度 UI 还未落地；当前统一注册契约已预留，但活跃 provider 仍以 Codex 为主。
- OpenClaw Gateway 到 Codex CLI 的直连 RPC、无 UI/headless 常驻执行、远程调度不在 `v0.4` 交付范围内。
- `Tasks` 与 `Memory` 相关能力仍以 truth 收口为主，没有新增伪造接口或误导性交互。

### Known Issues
- 全量 `flutter analyze` 仍失败，主要被 `test/runtime/codex_integration_test.dart` 的既有编译损坏拖住。
- 全量 `flutter test` 仍有既有失败项，包括：
  - `test/features/settings_page_test.dart` 的旧断言失败
  - `test/runtime/mode_switcher_test.dart` 的旧超时/失败
  - `test/runtime/app_controller_codex_bridge_test.dart` 在受限环境下写 `~/.codex/config.toml` 的权限问题
- macOS device-run 集成用例仍不稳定：
  - `integration_test/desktop_navigation_flow_test.dart` 仍引用旧入口文案
  - `integration_test/desktop_settings_flow_test.dart` 仍受 `Failed to foreground app; open returned 1` 影响

### Dev
- `pubspec.yaml`: 当前版本保持 `0.4.0+2`
- `CodexBar/version.env`: 营销版本保持 `0.4.0`
