# 2026-03-14 Codex External Cooperative Mode

## 目标

按 external-first 顺序完成 XWorkmate 的 Code Agent 集成：

1. 先交付外部 Codex CLI 协同模式
2. 同时保留其他外部 CLI 的统一接入 contract
3. 内置 Codex / Rust FFI 延后

## 范围

### 包含

- `SettingsSnapshot.codeAgentRuntimeMode`
- `SettingsSnapshot.codexCliPath`
- Codex bridge control panel
- 外部 Codex CLI 显式启停
- AI Gateway 配置导出 / 写入
- OpenClaw `agent/register` 协同注册
- `chat.send` 的 app-mediated node metadata
- Gateway 不可用时的本地降级

### 不包含

- 自动开机启动 bridge
- 其他 provider 的选择 UI
- 任务写接口
- 记忆 CRUD
- Rust FFI 实现

## 关键实现点

### 设置与状态

- `builtIn` 保留在运行时枚举中，作为 experimental 选项可见但不作为稳定交付承诺
- `codexCliPath` 与 `cliPath` 分离：
  - `codexCliPath` 仅用于 Codex CLI
  - `cliPath` 继续用于 OpenClaw/bootstrap CLI

### Bridge 顺序

1. 校验 AI Gateway URL 和 Codex binary
2. 调用 `configureCodexForGateway()`
3. 启动外部 Codex CLI
4. 通过 `CodeAgentNodeOrchestrator` 生成 App node dispatch metadata
5. Gateway 已连接时执行 `agent/register`

### 协同 metadata

- `providerId = codex`
- `runtimeMode = externalCli`
- `transport = stdio-bridge`
- capabilities:
  - `chat`
  - `code-edit`
  - `gateway-bridge`
  - `memory-sync`

## 涉及文件

- `lib/runtime/runtime_models.dart`
- `lib/runtime/runtime_coordinator.dart`
- `lib/runtime/code_agent_node_orchestrator.dart`
- `lib/runtime/agent_registry.dart`
- `lib/app/app_controller.dart`
- `lib/features/ai_gateway/ai_gateway_page.dart`
- `lib/features/tasks/tasks_page.dart`

## 验收

### 自动化

- `SettingsSnapshot` 序列化测试
- `RuntimeCoordinator` 外部 / built-in 行为测试
- `AgentRegistry` transport metadata 测试
- `AppController.enableCodexBridge()` 协同注册与降级测试
- Tasks Scheduled 只读 widget test

### 人工

- 已安装 `codex` 且 AI Gateway 已配置
- Gateway 在线时检查一次 `agent/register`
- Gateway 离线时检查 bridgeOnly 降级
- UI 中 Built-in 始终显示为 experimental
