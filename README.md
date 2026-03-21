# XWorkmate

XWorkmate is an AI workspace shell built with Flutter.
`v0.5` ships persistent assistant task threads, optional ARIS-powered multi-agent collaboration, and a bundled Go bridge runtime that travels with the macOS app.

## v0.5 Highlights

- Assistant 任务线程支持流式回复、继续追问和手动归档，不再是一问一答即结束。
- 任务列表按 `仅 AI Gateway / 本地 OpenClaw Gateway / 远程 OpenClaw Gateway` 分组显示。
- Multi-Agent 协作支持 `Architect / Engineer / Tester`，并可切换 `Native / ARIS` 框架。
- ARIS `skills/` 直接随 App 内置，`llm-chat` 与 `claude-review` 统一由 Go bridge 驱动。
- `Ollama Cloud` 设置、ARIS helper bundling、macOS DMG 打包与安装链路已打通。

## Current Scope

### Shipping in v0.5
- AI Gateway-only streaming assistant threads
- OpenClaw local/remote task threads with persistent context
- Multi-Agent orchestration with optional ARIS preset
- Bundled ARIS skills, Go bridge helper, `llm-chat` reviewer, and `claude-review`
- Ollama Cloud settings, task grouping, and macOS packaged delivery
- Flutter Web shell with `Assistant` + `Settings` only, supporting `Direct AI Gateway` and `Relay OpenClaw Gateway`

### Not Yet Implemented
- Built-in Codex runtime through Rust FFI
- Distributed/headless remote worker orchestration
- Generic external Code Agent provider chooser / scheduler UI beyond current role-based settings
- Expanded task CRUD beyond the current assistant-thread-first workflow
- Expanded memory APIs beyond `memory/sync`

## Known Issues

- ARIS local-first collaboration still depends on a reachable local Ollama endpoint for the strongest offline workflow.
- Cloud CLI roles still degrade to locally available executors when Gemini / Claude / Codex are not installed.
- Manual validation is still recommended for full end-to-end multi-agent runs that touch external CLIs.

## Development

```bash
flutter analyze
flutter test
flutter test --platform chrome test/widget_test.dart test/web
flutter run -d macos
```

## Flutter Web

Web keeps the Assistant-first entry flow, but only exposes:

- `Assistant`
- `Settings`
- `Direct AI Gateway`
- `Relay OpenClaw Gateway`

Web does not expose local CLI, workspace file access, native runtime orchestration, or desktop-only diagnostics.

Build the root-site bundle with:

```bash
flutter build web --release --base-href /
```

Deployment notes for `https://xworkmate.svc.plus/` are in [docs/web-deployment.md](/Users/shenlan/workspaces/cloud-neutral-toolkit/XWorkmate.svc.plus/docs/web-deployment.md).

## macOS Packaging

```bash
make package-mac
make install-mac
```

## Vendor Repositories

`vendor/codex` is tracked as a git submodule for future built-in code agent integration.

```bash
git submodule update --init --recursive
```
