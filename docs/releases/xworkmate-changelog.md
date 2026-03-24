# XWorkmate Changelog

> Historical changelog normalized for `v0.1` through `v0.7`.
> Snapshot rule: prefer release tag; if no tag exists, use the release branch snapshot.
> Special case: `v0.3` is recorded from `release/v0.3` because no `v0.3` tag exists in git.

## Release Sequence

| Version | Date | Snapshot Ref | Branch | Version String |
| --- | --- | --- | --- | --- |
| `v0.7` | `2026-03-24` | `v0.7` | `release/v0.7` | `0.7.0+1` |
| `v0.6.1` | `2026-03-22` | `v0.6.1` | `main` hotfix | `0.6.1+1` |
| `v0.6` | `2026-03-22` | `v0.6` | `release/v0.6` | `0.6.0+1` |
| `v0.5` | `2026-03-20` | `v0.5` | `release/v0.5` | `0.5.0+1` |
| `v0.4` | `2026-03-15` | `v0.4` | `release/v0.4` | `0.4.0+2` |
| `v0.3` | `2026-03-13` | `release/v0.3` | `release/v0.3` | `latest` |
| `v0.2` | `2026-03-12` | `v0.2` | `release/v0.2` | `2026.3.11+20260311` |
| `v0.1` | `2026-03-11` | `v0.1` | `release/v0.1` | `2026.3.11+20260311` |

## Matrix Availability

| Version | Feature Matrix |
| --- | --- |
| `v0.7` | `mobile 26/18/18/6`, `desktop 26/20/19/5`, `web 8/8/8/7` |
| `v0.6.1` | `mobile 27/19/19/2`, `desktop 27/21/20/1`, `web 8/8/8/4` |
| `v0.6` | `mobile 28/19/19/1`, `desktop 28/22/21/0`, `web 8/8/8/4` |
| `v0.1` - `v0.5` | feature flag manifest not yet introduced |

## Per-Version Log

### `v0.7` — `2026-03-24`

**Highlights**

- 新增 ACP 外部接入设置页和 provider 级 endpoint 配置。
- Single Agent 与外部 ACP 链路完成真实协议打通。
- 持久化和打包分发路径延续收敛到文件存储布局。

**FIX**

- `f1a4793` Fix Codex ACP turn payload schema
- `a734d34` Fix single-agent ACP model ownership
- `23d8974` Fix secrets settings tab assertion
- `32ef635` Fix codex external CLI availability detection with configured path
- `fbc4f55` fix(release): harden apple app store distribution

**Refactors**

- `82a33b8` refactor(desktop): route assistant execution through gateway ACP
- `b53b853` refactor: rename AI Gateway UI copy to LLM API
- `7540a3a` refactor(appstore): use external single-agent app-server
- `c7101bf` Remove legacy persistence implementation
- `22ceb3b` Rebuild desktop persistence as file stores

**Issue Notes**

- 发布说明中仍保留全量 `flutter test` 的既有失败和 macOS foreground flake。

### `v0.6.1` — `2026-03-22`

**Highlights**

- secure config / settings / secret store 的 fallback、回写和初始化逻辑进一步补齐。
- Integrations 与 gateway profiles 被收拢到统一 settings center。
- remote thread status fallback 修复后，线程状态回退逻辑更稳。

**FIX**

- `95ae875` Fix remote thread status fallback
- `98409d1` Refine AI Gateway action buttons

**Refactors**

- `ffced7f` Refactor settings persistence and upgrade recovery
- `abea2b4` Integrate gateway settings into integrations page
- `72ecd1f` Unify legacy config pages into settings center
- `5d49ae3` Refactor assistant page and gateway runtime integration
- `5cab0f5` Refactor work modes and gateway profiles

**Issue Notes**

- 没有找到独立 hotfix issue 清单；后续 `v0.7` 区间继续处理持久化测试、外部 ACP 文案和设置交互。

### `v0.6` — `2026-03-22`

**Highlights**

- secure-storage 加密持久化正式进入主线。
- Single Agent 本地技能发现与线程恢复补齐。
- Web / mobile / desktop 多端可用性与 build-and-release 链路同步增强。

**FIX**

- `8f655d3` Fix web chrome test isolation and session persistence
- `10717a0` fix(runtime): encrypt local settings and assistant thread persistence
- `09287cc` Fix assistant thread connection status
- `50f38e8` Fix assistant composer shell height adaptation
- `4ea4c06` Fix assistant execution target switch refresh timing

**Refactors**

- `7793e92` refactor: unify settings drill-in navigation
- `0d3b9b1` refactor: align multi-agent workflow with real ollama cli
- `c24f2ab` feat: add ui feature flag release docs pipeline
- `77ab128` Persist assistant state and add local recovery cleanup

**Issue Notes**

- release notes 明确记录：外部 CLI / Gateway 依赖环境、macOS integration 串行执行问题仍在。

### `v0.5` — `2026-03-20`

**Highlights**

- 流式 assistant 线程、任务归档与重启恢复落地。
- 任务列表按执行目标分组。
- Multi-Agent runtime、ARIS bundle 和 Go bridge runtime 进入可交付状态。

**FIX**

- `09ef2ea` Fix settings page layout and AI Gateway persistence
- `7c98ab3` Fix AI Gateway-only assistant flow
- `41e0632` Fix assistant model routing and task naming
- `039ce2d` Fix AI Gateway-only UTF-8 chat flow
- `0438dc5` Repair codex integration test baseline

**Refactors**

- `4f887e4` feat: add linux desktop parity scaffolding
- `f0070c6` feat: align Windows desktop runtime with macOS parity
- `02a0f89` feat: add shared compact mobile shell
- `b9cdb7d` Add managed multi-agent collaboration runtime
- `47473e0` Integrate ARIS bundle and Go bridge runtime
- `6280e75` Stabilize ARIS packaging and Ollama Cloud settings

**Issue Notes**

- 发布说明明确保留：built-in Codex / Rust FFI 未交付、通用 provider 调度 UI 未完成、外部 CLI 全链路仍需人工验证。

### `v0.4` — `2026-03-15`

**Highlights**

- Assistant 成为默认主页。
- 任务、导航、关注入口、面包屑和动态侧板整合为统一工作台。
- external-first Codex 路线成形。

**FIX**

- `430272d` fix: remove undefined _CodexBridgeCard reference to fix build
- `04b52c3` fix: resolve Rust FFI compilation errors and simplify build
- `9c47eef` fix: show assistant task rail on desktop

**Refactors**

- `e87df77` refactor(ui): modernize design system with consistent spacing and typography
- `8199f2a` refactor: 重命名 MCP Server 为 MCP Hub
- `f541e9e` feat(runtime): add built-in/external codex modes and external agent provider registry
- `cacdb70` feat: expand codex bridge integration and assistant workspace
- `2e467fa` feat: unify assistant sidebar and task list

**Issue Notes**

- 当时 release notes 已单列 `flutter analyze`、`flutter test` 和 macOS device-run 的既有失败。

### `v0.3` — `2026-03-13`

**Highlights**

- AI Gateway integration 与 UI polish 完成一轮补齐。
- paired device 状态与桌面版面密度得到收敛。

**FIX**

- `7ea6e0d` fix: simplify paired device status display
- `3dfb444` fix: trim wasted desktop page bottom spacing

**Refactors**

- `02a2e5c` refactor: normalize desktop typography and density
- `edd46d6` chore: unify version to v0.2 with build-date and build-id

**Issue Notes**

- 该版本无正式 tag，也无独立 release notes；本段基于 `v0.2..release/v0.3` 提交区间整理。

### `v0.2` — `2026-03-12`

**Highlights**

- gateway-driven assistant baseline 完成。
- device pairing controls、diagnostics log viewer、secure shared token handling 首次落地。

**FIX**

- `7a86703` fix: improve remote gateway bootstrap prefill
- `acc3a06` fix: stabilize remote gateway pairing identity

**Refactors**

- 该版本仍处于早期基线期，主要新增以功能交付为主，重构记录较少。

**Issue Notes**

- 后续 `v0.3` 才继续补齐 AI Gateway integration polish、密度和状态展示收口。

### `v0.1` — `2026-03-11`

**Highlights**

- 初始 Flutter workspace shell 和桌面工作区结构建立。
- tri-state sidebar、resizable layout、语言切换、macOS App Store 准备项到位。

**FIX**

- `09d29f6` Fix expanded sidebar navigation layout
- `7693de2` Reduce minimum sidebar width

**Refactors**

- `486e9aa` Move composer actions menu to the left
- `af5098c` Polish workspace theme and add Makefile tasks
- `f179a11` Simplify expanded sidebar action tiles
- `518549b` Remove expanded sidebar header title

**Issue Notes**

- 后续 `v0.2` 才引入 gateway-driven assistant、诊断日志和配对能力，说明 `v0.1` 仍是 UI 与打包基线版本。
