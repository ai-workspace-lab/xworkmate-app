# XWorkmate Release Notes

> Curated historical release record for `v0.1` through `v0.7`.
> Sources: git tags / release branches, `CHANGELOG.md`, and `config/feature_flags.yaml` when present.
> Note: `config/feature_flags.yaml` does not exist in `v0.1` through `v0.5`, so those versions do not have a first-class feature flag matrix baseline.

## Release Ledger

| Version | Date | Snapshot Ref | Branch | Matrix Source |
| --- | --- | --- | --- | --- |
| `v0.7` | `2026-03-24` | `v0.7` | `release/v0.7` | `config/feature_flags.yaml` |
| `v0.6.1` | `2026-03-22` | `v0.6.1` | `main` hotfix | `config/feature_flags.yaml` |
| `v0.6` | `2026-03-22` | `v0.6` | `release/v0.6` | `config/feature_flags.yaml` |
| `v0.5` | `2026-03-20` | `v0.5` | `release/v0.5` | not yet introduced |
| `v0.4` | `2026-03-15` | `v0.4` | `release/v0.4` | not yet introduced |
| `v0.3` | `2026-03-13` | `release/v0.3` | `release/v0.3` | not yet introduced |
| `v0.2` | `2026-03-12` | `v0.2` | `release/v0.2` | not yet introduced |
| `v0.1` | `2026-03-11` | `v0.1` | `release/v0.1` | not yet introduced |

## Matrix Baseline

| Version | Mobile D/P/R/S | Desktop D/P/R/S | Web D/P/R/S | Visible Flags R/P/D |
| --- | --- | --- | --- | --- |
| `v0.7` | `26 / 18 / 18 / 6` | `26 / 20 / 19 / 5` | `8 / 8 / 8 / 7` | `45 / 46 / 60` |
| `v0.6.1` | `27 / 19 / 19 / 2` | `27 / 21 / 20 / 1` | `8 / 8 / 8 / 4` | `47 / 48 / 62` |
| `v0.6` | `28 / 19 / 19 / 1` | `28 / 22 / 21 / 0` | `8 / 8 / 8 / 4` | `48 / 49 / 64` |

## Version Notes

### `v0.7` — `2026-03-24`

**Feature Matrix**

- `release` 可见 45 个 flags，`profile` 46 个，`debug` 60 个。
- 相比 `v0.6.1`，`release` 少 2 个、`debug` 少 2 个，重点是收敛实验入口和未完备设置项。

**Highlights**

- 新增 `ACP 外部接入`，为 `Codex / OpenCode / Claude / Gemini` 提供独立 endpoint 配置。
- Single Agent 外部 ACP 模式改为显示 ACP 实际运行时模型，不再错误复用本地 LLM API 模型。
- Codex ACP `thread/start` / `turn/start` / `input` item 协议打通，真实 WebSocket 任务链路可用。
- 文件持久化布局稳定为 `settings.yaml`、`tasks/*.json`、`secrets/*.secret`。

**Fixes**

- 修复 Codex ACP turn payload schema。
- 修复 single-agent ACP 模型归属。
- 修复 secrets settings tab assertion 和外部 CLI 可用性检测。
- 修复 macOS package build state reset，继续加固 App Store 分发。

**Refactors**

- assistant 执行链路切到 gateway ACP。
- `AI Gateway` UI 文案统一收口到 `LLM API` / `Single Agent`。
- 外部 single-agent app-server 用于 App Store 分发路径。

**Known Issues**

- `flutter test` 全量仍有既有失败：`assistant_page_test` 的 pending timer 与 `modules_page_test` 的重复文案断言。
- macOS device-run 仍可能触发 `Failed to foreground app; open returned 1`，需要串行执行并配合人工检查。

### `v0.6.1` — `2026-03-22`

**Feature Matrix**

- `release` 可见 47 个 flags，`profile` 48 个，`debug` 62 个。
- 相比 `v0.6`，矩阵整体略有收口，重点是把账号等未完备入口继续降级或关闭。

**Highlights**

- `SecureConfigStore`、`SettingsStore`、`SecretStore` 补齐标准目录 fallback 与首次启动目录准备。
- 持久化改为默认 fail-fast，避免数据库或路径异常时静默退回内存。
- 显式内存 fallback 模式补齐“尽力回写”。
- `mobile.workspace.account` 与 `desktop.navigation.account` 被关闭为 `experimental` 且 `enabled: false`。

**Fixes**

- 修复 remote thread status fallback。
- 补齐路径失败报错与跨实例持久化回归覆盖。
- 收紧 Gateway settings 的动作按钮与集成入口切换。

**Refactors**

- settings persistence / upgrade recovery 重构。
- gateway settings 并入 Integrations 页。
- 旧配置页统一并入 settings center。
- assistant 页面、gateway runtime、work mode / profile 结构重构。

**Known Issues**

- 没有找到独立的 `v0.6.1` issue 列表；从后续 `v0.7` 提交可见，持久化测试基线、外部 ACP 文案和设置交互在该版本后仍继续修整。

### `v0.6` — `2026-03-22`

**Feature Matrix**

- `release` 可见 48 个 flags，`profile` 49 个，`debug` 64 个。
- `desktop` 在 `debug` 下暴露 28 个可见条目，是当时最完整的平台面。

**Highlights**

- 本地配置、Gateway 凭证与 Assistant 线程会话改为 secure-storage 驱动的加密持久化。
- Single Agent 线程补齐本地技能自动发现与线程内可选技能恢复。
- Flutter Web assistant shell、Web Chrome 持久化、移动端安全控件一并补齐。
- Windows / Linux parity、多平台 build-and-release、macOS 安装分发流程完成一轮系统化增强。

**Fixes**

- 修复 web chrome test isolation 和会话持久化。
- 修复 assistant thread connection status、composer shell 高度自适应、execution target 切换刷新时序。
- 修复运行时本地 settings 与 assistant thread persistence 的加密持久化实现。

**Refactors**

- 新增 UI feature flag release docs pipeline。
- settings drill-in navigation 与多智能体工作流按真实 ollama CLI 统一。
- assistant composer shell sizing、local recovery cleanup、IA 文档一并梳理。

**Known Issues**

- 外部 CLI / 远程 Gateway 协同仍依赖宿主安装和网络可达性，需要按 case 文档补人工验收。
- macOS integration 测试仍可能受到宿主前台拉起行为影响，需要串行执行。

### `v0.5` — `2026-03-20`

**Feature Matrix**

- `config/feature_flags.yaml` 尚未进入仓库，无法回放标准化的 D/P/R/S 矩阵。
- 该版本的“功能矩阵”主要体现在运行模式与平台面扩展，而不是 feature flag 清单。

**Highlights**

- Assistant 线程升级为持续会话，支持流式回复、继续追问、线程归档与重启恢复。
- 任务列表按 `Single Agent / 本地 OpenClaw Gateway / 远程 OpenClaw Gateway` 分组。
- Multi-Agent 协作升级为 `Architect / Engineer / Tester`，并可挂载 `ARIS`。
- ARIS bundle 与 Go runtime 被内嵌到 App 分发链路。

**Fixes**

- 修复 AI Gateway-only assistant flow、模型路由、任务命名与 UTF-8 chat flow。
- 修复 settings page layout 与 AI Gateway persistence。
- 修复 codex integration test baseline。

**Refactors**

- Linux / Windows / Android parity 支线合回主线。
- 桌面 workspace chrome、typography density、gateway dialog、theme surface 做了一整轮压缩与统一。
- assistant execution target、task list grouping、multi-agent runtime 与 ARIS bridge 被整体重组。

**Known Issues**

- 内置 Codex / Rust FFI 仍未交付，仍是 placeholder。
- 通用外部 Code Agent provider chooser / 调度 UI 尚未落地。
- 外部 CLI 全链路协作仍建议按 `docs/cases/README.md` 做手动验证。

### `v0.4` — `2026-03-15`

**Feature Matrix**

- `config/feature_flags.yaml` 尚未引入。
- 该版本更适合用“桌面工作台结构矩阵”理解：Assistant 成为默认主页，任务、导航、收藏入口和面包屑完成统一。

**Highlights**

- Assistant 成为默认主页，首页围绕默认任务工作台展开。
- 左侧侧板统一为 `任务 / 导航` 加关注入口，支持折叠、拖拽和动态宽度。
- 任务列表与当前对话打通，会话默认作为任务上下文持续保留。
- Codex 路线明确为 external-first，经由 XWorkmate 与 OpenClaw Gateway 协同。

**Fixes**

- 修复 undefined `_CodexBridgeCard` 构建错误。
- 修复 Rust FFI 编译错误并简化构建。
- 修复桌面 assistant task rail 显示。

**Refactors**

- 现代化 design system、统一 spacing 与 typography。
- 左侧边栏导航结构、MCP Hub 命名、assistant focused navigation、favorites 与 breadcrumbs 整体重构。
- built-in / external Codex modes 和 external agent provider registry 在该版本区间内成形。

**Known Issues**

- `flutter analyze` 仍受 `test/runtime/codex_integration_test.dart` 的既有编译问题影响。
- `flutter test` 仍有 settings、mode switcher、Codex bridge 相关既有失败。
- macOS device-run 集成用例仍不稳定。

### `v0.3` — `2026-03-13`

**Feature Matrix**

- `config/feature_flags.yaml` 尚未引入。
- 可确认的功能面来自 `v0.2..release/v0.3` 提交区间，而不是标准 feature flag 快照。

**Highlights**

- 补齐 AI Gateway integration 与一轮桌面 UI polish。
- paired device 状态展示进一步简化。
- 版本号统一为 `v0.2` marketing 体系并补 build-date / build-id。

**Fixes**

- 修复 paired device status display。
- 修复桌面页面底部空白过大问题。

**Refactors**

- 桌面 typography 与 density 规范化。

**Known Issues**

- 推断：该版本尚未包含 `v0.4` 才形成的 built-in / external Codex mode、任务工作台整合与侧栏收藏体系。
- 推断：尚未形成正式 release notes / issue 清单流程。

### `v0.2` — `2026-03-12`

**Feature Matrix**

- `config/feature_flags.yaml` 尚未引入。
- 该版本以 Gateway-driven assistant baseline 为中心，而非 feature flag 管理模型。

**Highlights**

- 完成 gateway-driven assistant baseline。
- 新增 gateway device pairing controls。
- 新增 runtime diagnostics log viewer。
- 引入 secure gateway shared token handling。

**Fixes**

- 改善 remote gateway bootstrap prefill。
- 稳定 remote gateway pairing identity。

**Refactors**

- 版本号与 build-date / build-id 体系在下一版本区间被统一，说明此版本仍处于早期打包策略磨合阶段。

**Known Issues**

- 推断：AI Gateway integration UI polish、设备状态精简与桌面 density 规范化仍未完成，这些能力在 `v0.3` 才落地。
- 推断：尚未引入正式 release docs 与 feature matrix 工具链。

### `v0.1` — `2026-03-11`

**Feature Matrix**

- `config/feature_flags.yaml` 尚未引入。
- 该版本是桌面 workspace shell 基线，记录方式以 UI 结构和打包准备为主。

**Highlights**

- 建立 Flutter workspace shell 与初始桌面工作区结构。
- 增加 assistant access controls、桌面窗口最大化与全局中英语言切换。
- 完成 tri-state sidebar、resizable workspace layout 和一轮主题打磨。
- 补齐 macOS App Store release workspace 与 category metadata。

**Fixes**

- 修复 expanded sidebar navigation layout。
- 降低 sidebar 最小宽度并压缩 expanded sidebar 宽度。

**Refactors**

- composer actions menu 左移。
- expanded sidebar footer、action tiles、header title 进行了一整轮收口简化。
- theme 与 Makefile tasks 一并整理，形成最初的工程基线。

**Known Issues**

- 推断：Gateway-driven assistant、设备配对、诊断日志、secure token handling 仍未进入产品面，这些能力在 `v0.2` 才补齐。
- 推断：尚未形成 release docs、feature flags 与版本 issue 清单机制。
