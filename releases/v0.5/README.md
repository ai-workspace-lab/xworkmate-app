# XWorkmate v0.5 Release

## Version

- Marketing version: `0.5.0`
- Build number: `1`
- Tag: `v0.5`

## Release Focus

- 持续 Assistant 任务线程与流式 AI Gateway 对话
- `单机智能体 / 本地 OpenClaw Gateway / 远程 OpenClaw Gateway` 三模式统一
- `Architect / Engineer / Tester` 多 Agent 协作
- 可选 `ARIS` 框架、内嵌 skills、Go core runtime
- `Ollama Cloud` 文案和默认地址统一

## Bundled Runtime

- `assets/aris/skills` 继续直接复用 upstream `skills/`
- `llm-chat` 与 `claude-review` 统一由 `xworkmate-go-core` 提供
- macOS `.app` 会把 helper 打进 `Contents/Helpers/xworkmate-go-core`

## Validation

- `flutter analyze`
- `flutter test`
- `cd go/go_core && go test ./...`
- `flutter test integration_test/desktop_navigation_flow_test.dart -d macos`
- `flutter test integration_test/desktop_settings_flow_test.dart -d macos`
- `flutter build macos`
- `flutter build ios --simulator`
- `make install-mac`

## Manual Cases

- `docs/cases/README.md`
