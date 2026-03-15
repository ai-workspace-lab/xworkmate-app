# XWorkmate

XWorkmate is a desktop-first AI workspace shell built with Flutter.  
`v0.4` ships the assistant workbench as the default homepage and treats XWorkmate itself as the cooperative node connected to OpenClaw Gateway.

## v0.4 Highlights

- Assistant 首页默认落在“默认任务”工作台。
- 左侧统一侧板支持固定 `任务 / 导航` 与自定义关注入口。
- 当前对话默认作为任务上下文持续保留，归档后才从列表隐藏。
- 外部 Codex CLI 已可通过 app-mediated bridge 方式接入，并与 AI Gateway / OpenClaw Gateway 协同工作。
- macOS 已具备 DMG 打包与安装链路。

## Current Scope

### Shipping in v0.4
- External-first Codex CLI integration
- AI Gateway model bridge
- OpenClaw Gateway cooperative registration through XWorkmate
- Assistant task workspace with focused-entry side panel
- Breadcrumb navigation and dynamic left-panel resizing

### Not Yet Implemented
- Built-in Codex runtime through Rust FFI
- Gateway-to-Codex direct RPC, headless execution, or remote scheduling
- Generic external Code Agent provider chooser / scheduler UI
- Expanded task CRUD beyond `cron.list` read-only visibility
- Expanded memory APIs beyond `memory/sync`

## Known Issues

- Full `flutter analyze` still fails because of existing issues, mainly `test/runtime/codex_integration_test.dart`.
- Full `flutter test` still has existing failures in settings/runtime tests and Codex bridge permission-sensitive cases.
- macOS device-run integration tests still rely on stale selectors and can fail to foreground the app during automated runs.

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
