# XWorkmate

XWorkmate is a desktop-first AI workspace shell built with Flutter.  
`v0.5` ships persistent assistant task threads, optional ARIS-powered multi-agent collaboration, and a bundled Go bridge runtime that travels with the app.

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
flutter run -d macos
```

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
