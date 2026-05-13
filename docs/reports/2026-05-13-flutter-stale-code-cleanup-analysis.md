# Flutter/Dart 孤立代码与陈旧代码清理分析

日期：2026-05-13

范围：

- `lib/settings/mobile/runtime`：目录不存在
- `lib/gateway`：目录不存在
- `lib/profile`：目录不存在
- `lib/shared/shell`：目录不存在
- `lib/widgets/layout`：目录不存在
- `lib/core/helper`：目录不存在
- `lib/core/utils`：目录不存在
- 已扫描仍存在的重点路径：`lib/runtime`、`lib/features/settings`、`lib/features/mobile`、`lib/widgets`、`lib/app`

## 已执行扫描

- `rg "^export " lib test`
- `find lib -name "*.dart"`
- `rg "^class |^typedef |^extension |^mixin "`
- `rg "register|registry|routes:|GoRoute|GetIt|Provider|Riverpod|dispatch|mount|factory|builder:|runtimeType"`
- `rg "legacy|deprecated|old|helper|tmp|unused|v1|backup|compat|fallback"`

## Safe To Remove

本轮已删除：

- `lib/app/app_controller_desktop_single_agent.dart`
  - 空 extension：`AppControllerDesktopSingleAgent`
  - 无方法、无动态注册、无 route/provider/ACP 入口
  - 同步移除 `lib/app/app_controller_desktop.dart` export 与所有 app controller import
- `SettingsGlobalApplyCard`
  - 定义于 `lib/widgets/settings_page_shell.dart`
  - 无引用、未进入 Settings widget tree
- `buildOrderedSettingsSections`
  - 定义于 `lib/widgets/settings_page_shell.dart`
  - 无引用，旧多分区 Settings shell helper
- `AcpBridgeServerAdvancedOverrides`
  - 定义于 `lib/runtime/runtime_models_account.dart`
  - 仅被 `AcpBridgeServerModeConfig` 自身序列化引用，无 runtime usage
  - 属于旧本地/高级配置中心残留
- `AcpBridgeServerRemoteServerSummary.hasAdvancedOverrides`
  - 仅写入固定 false，无业务消费
- `AccountTokenConfigured.apisix` 与 `AccountRemoteProfile.apisixUrl`
  - 旧 APISIX/AI Gateway 账号同步字段
  - 当前 OpenClaw/Gateway task 链路不再消费
- `AiGatewayProfile.fromJson(filePath -> baseUrl)` fallback
  - 旧字段兼容路径
- `SettingsSnapshot.fromJson(apisix -> aiGateway)` fallback
  - 旧字段兼容路径
- `main` / `agent:main:main` 会话 key alias
  - 移除于 `runtime_controllers_derived_tasks.dart`
  - 移除于 `assistant_page_task_models.dart`

## Probably Removable

以下仍需按业务闭包继续拆，不建议一次性自动删除：

- `lib/data/mock_data.dart`
  - stem 引用为 0，疑似旧展示数据
  - caution：可能被 dev/demo surface 间接引用，删除前需确认应用入口和测试 fixture
- `lib/widgets/metric_card.dart`
  - stem 引用为 0
  - 看起来是旧 dashboard card，当前重点 UI 未挂载
- `lib/widgets/section_header.dart`
  - stem 引用为 0
  - 可能是旧页面布局 helper
- `lib/widgets/app_brand_logo.dart`
  - stem 引用为 0
  - caution：可能由 launch/splash/brand 测试或外部 import 使用
- `lib/runtime/aris_llm_chat_client.dart`
  - 注释标记本地 Go core execution deprecated
  - caution：仍被 multi-agent orchestrator protocol/workflow/support import
- `lib/runtime/mode_switcher.dart`
  - 仍被 runtime coordinator 与 app controller 多处使用
  - 不应直接删，后续应评估 Gateway mode 是否还需要 app-side mode switcher

## Dynamic Runtime Bound

以下存在动态入口或 runtime 注册，不应自动删除：

- `lib/app/workspace_page_registry.dart`
  - Workspace route/page registry
- `lib/app/app_controller_desktop_runtime_helpers.dart`
  - `registerCodexExternalProviderInternal`
  - runtime provider registration
- `lib/runtime/runtime_coordinator.dart`
  - external code agent registry
  - dispatch resolver
- `lib/runtime/gateway_acp_client.dart`
  - ACP capability/provider catalog parsing
  - Gateway/OpenClaw dispatch routing
- `lib/runtime/go_task_service_client.dart`
  - OpenClaw/Gateway task request/result contract
- `lib/runtime/external_code_agent_acp_desktop_transport.dart`
  - ACP transport capability parse path
- `lib/runtime/agent_registry.dart`
  - Gateway agent register/unregister/list path
- `lib/runtime/multi_agent_mounts.dart`
  - mount adapter registration and reconcile path

## Legacy Compatibility Layer

已清理：

- `AcpBridgeServerAdvancedOverrides`
- APISIX account sync fields
- AiGateway old `filePath` fallback
- SettingsSnapshot old `apisix` fallback
- runtime `main`/`agent:main:main` session alias

保留但标记 caution：

- `SecretStore.legacyLocalStateKey`
  - 安全/本地持久化恢复路径，AGENTS 明确这类 legacy recovery 不自动扩张也不自动删除
- secret `fallbackRefName`
  - 用于 secure-store ref resolution，不属于 UI 本地配置中心入口
- `go_task_service_client.dart` 的 failure text fallback
  - task terminal-state 文本兜底，后续应继续收敛到结构化 code

## Export Cleanup

当前 barrel 扫描：

- `lib/app/app_controller_desktop.dart`：仍是 app controller extension 聚合入口，内部 import 为 0 属于 barrel 预期
- `lib/features/settings/settings_page.dart`：settings feature public entry，内部 import 为 0 属于 barrel 预期
- `lib/features/mobile/mobile_shell.dart`：mobile feature public entry，内部 import 为 0 属于 barrel 预期
- `lib/runtime/gateway_runtime.dart`、`lib/runtime/multi_agent_orchestrator.dart`、`lib/runtime/runtime_models.dart`：runtime public barrel，动态/测试入口仍依赖

本轮已清理的 export：

- `lib/app/app_controller_desktop.dart` 不再 export `app_controller_desktop_single_agent.dart`

## Unreachable Widget Tree

已删除：

- Settings 全局 apply card
- Settings 多分区排序 helper

仍在 widget tree：

- `SettingsPage`
  - 通过 `workspace_page_registry.dart` 挂载
- `SettingsAccountPanel`
  - 通过 `SettingsPage` 挂载
- `SettingsAboutPanel`
  - 通过 `SettingsPage` 挂载
- `MobileShell`
  - 通过 `AppShell` responsive surface 挂载
- `MobileGatewayPairingGuidePage`
  - 通过 `MobileShell` pairing flow 挂载
- `AssistantFocusPanel`
  - 预览组件仍由 assistant focus panel 内部分发

## Refactor Suggestions

- 继续收敛 `SettingsSnapshot`：把不再有 UI 的 Vault/Ollama/AiGateway 配置按实际 runtime 使用拆分，避免 Settings model 继续承担旧配置中心职责。
- 后续单独评估 `lib/data/mock_data.dart`、`MetricCard`、`SectionHeader`、`AppBrandLogo` 是否仍有真实入口。
- 对 `runtime_controllers_settings*.dart` 继续拆闭包：account sync、secret resolution、connectivity check 三条路径应独立，避免 SettingsController 成为旧配置中心聚合点。
- 对 `go_task_service_client.dart` terminal-state fallback 继续结构化，减少文本兜底。
