# XWorkmate Public API Engineering Docs

Last Updated: 2026-04-14

## Purpose

本目录为 `xworkmate-app` 的公开接口工程文档下钻层，目标不是替代已有架构文档，而是把“当前主链真正暴露出来的库 / 类 / 函数 / 接口”系统化整理出来。

这一层文档固定采用两层产物：

- `机器清单层`：由脚本自动提取的公开符号与签名，解决“覆盖完整性”
- `设计解释层`：人工编写的职责、参数语义、返回值语义、主调用链、外部副作用，解决“可读性和工程决策语义”

## Reading Order

建议按下面顺序阅读：

1. [生成清单](_generated/public-symbol-inventory.md)
2. [App Orchestration](app-orchestration.md)
3. [Runtime Contracts](runtime-contracts.md)
4. [Feature Surfaces](feature-surfaces.md)
5. [Models And Config](models-and-config.md)
6. [FFI And Rust](ffi-and-rust.md)

再回看这些背景文档补架构上下文：

1. [XWorkmate Layered Architecture](../xworkmate-layered-architecture.md)
2. [XWorkmate Core Module Inventory](../xworkmate-core-module-inventory-2026-04-13.md)
3. [Task Control Plane Unification](../task-control-plane-unification.md)
4. [Settings Integration Configuration Model](../settings-integration-configuration-model.md)

## Scope Rule

纳入范围：

- `lib/app`
- `lib/runtime`
- `lib/models`
- `lib/features/assistant`
- `lib/features/settings`
- `lib/features/mobile`
- `lib/theme`
- `rust/src`

文档粒度：

- 公开顶层符号：非 `_` 开头的 `class`、`abstract class`、`enum`、`typedef`、`extension`
- 公开顶层函数
- Rust `pub struct` / `pub enum`
- Rust `pub unsafe extern "C"` FFI 函数

人工解释层的额外约束：

- 页面层只覆盖“业务 + 关键页面”
- 纯展示型 leaf widget 不逐条展开
- 私有 `_` 符号不作为正式 API 条目
- 低价值 DTO/辅助函数默认留在生成清单，不强行全部补人工说明

## Coverage Summary

当前生成清单覆盖 `130` 个源码文件、`614` 个公开符号。

| Scope | Files | Public Symbols | Detailed Design Entries | Notes |
| --- | ---: | ---: | ---: | --- |
| `lib/app` | 30 | 68 | 10 | 主写桌面编排入口、扩展、registry 与 shell |
| `lib/runtime` | 67 | 377 | 18 | 主写 bridge contract、runtime client、controller、bootstrap |
| `lib/models` | 1 | 34 | 13 | 主写 settings / execution / provider / snapshot 主模型 |
| `lib/features/assistant` | 16 | 80 | 1 | 只展开页面入口与业务挂点 |
| `lib/features/settings` | 4 | 4 | 1 | 只展开设置主入口 |
| `lib/features/mobile` | 6 | 19 | 1 | 只展开移动端 shell 主入口 |
| `lib/theme` | 2 | 13 | 2 | 只展开工程上影响 API 的 theme/palette 入口 |
| `rust/src` | 4 | 19 | 17 | 结构体与 FFI 函数全部展开 |

说明：

- “Public Symbols” 以生成清单 JSON 为准
- “Detailed Design Entries” 是人工解释层条目数，不等于全量公开符号数
- 剩余未逐条解释的公开符号，视为“已被生成清单覆盖，但尚未进入高价值解释层”

## Explicit Exclusions

下面这些内容被明确排除在“人工解释层”之外，但不代表它们不存在：

| Excluded Scope | Files | Public Symbols | Reason |
| --- | ---: | ---: | --- |
| `lib/widgets` | 21 | 51 | 纯展示 leaf widget 为主，不作为本次设计文档主对象 |
| `lib/data` | 1 | 1 | mock/sample 数据，不是运行时公开 contract |
| `lib/i18n` | 1 | 4 | 文案与语言辅助，不是业务接口主链 |
| `lib/main.dart` | 1 | 0 | 启动封装，无独立公开符号 |

## File Map

- [_generated/public-symbol-inventory.md](_generated/public-symbol-inventory.md)
  公开符号清单，适合做覆盖检查、文件定位、签名对照
- [_generated/public-symbol-inventory.json](_generated/public-symbol-inventory.json)
  机器可校验版本，适合后续脚本和 CI 使用
- [app-orchestration.md](app-orchestration.md)
  `AppController`、导航、设置保存、线程/会话/执行主链
- [runtime-contracts.md](runtime-contracts.md)
  ACP、gateway runtime、settings controller、session client、bootstrap、registry
- [feature-surfaces.md](feature-surfaces.md)
  `AssistantPage`、`SettingsPage`、`MobileShell`、`WorkspacePageSpec`
- [models-and-config.md](models-and-config.md)
  `SettingsSnapshot`、连接配置、provider/catalog、gateway/runtime snapshot、多 agent 配置
- [ffi-and-rust.md](ffi-and-rust.md)
  Rust 公开结构体与 C ABI 面

## Validation Workflow

生成清单：

```bash
make docs-public-api
```

最低校验：

```bash
python3 scripts/docs/extract_public_api_inventory.py
rg -n '`_' docs/architecture/public-api/*.md
```

人工核对优先文件：

- `lib/runtime/gateway_acp_client.dart`
- `lib/runtime/go_task_service_client.dart`
- `lib/runtime/codex_runtime.dart`
- `lib/app/app_controller_desktop_settings_runtime.dart`
- `rust/src/lib.rs`

## Maintenance Rule

- 新增公开顶层符号后，先运行 `make docs-public-api`
- 如果新增符号属于主链 contract、页面入口、配置主模型、桥接接口或 FFI 面，则必须补到人工解释层
- 如果只是低价值 DTO、单向 helper、视觉组件或简单枚举，允许仅由生成清单覆盖
