# 架构文档

## 核心架构

- [分层架构总览](./xworkmate-layered-architecture.md)
- [核心模块清单（2026-04-13）](./xworkmate-core-module-inventory-2026-04-13.md)
- [统一路由架构](./unified-routing-architecture.md)

## 桥接与运行时

- [Bridge 迁移方案](./xworkmate-bridge-migration.md)
- [Bridge 运行时路由映射](./bridge-runtime-routing-map.md)
- [Bridge 云共存优先级](./bridge-cloud-coexistence-priority.md)

## 会话与任务

- [任务控制面统一主线](./task-control-plane-unification.md)
- [任务线程 Session Key 隔离（2026-03-29）](./task-thread-session-key-isolation-20260329.md)
- [Task Dialog Provider 选择主线](./task-dialog-provider-selection-mainline.md)
- [跨仓库任务状态工作流](./cross-repo-task-state-workflow.md)
- [Cloud Session Service 多设备架构（2026-03-30）](./cloud-session-service-multi-device-architecture-2026-03-30.md)

## 设置与配置

- [Account Sync / Settings / Bridge 状态模型](./account-sync-settings-bridge-state-model.md)
- [Settings Integration 配置模型](./settings-integration-configuration-model.md)
- [安全本地持久化架构](./secure-local-persistence-architecture.md)

## 工程实践

- [Stage4 Helper 归属映射（2026-03-28）](./stage4-helper-ownership-20260328.md)
- [No-part 文件组织 ADR](./refactor-style-no-part-adr.md)
- [Simple Theme 默认值记录](./simple-theme-default.md)

## Public API 文档

- [Public API 阅读指南](./public-api/README.md)
- [App Orchestration](./public-api/app-orchestration.md)
- [Models & Config](./public-api/models-and-config.md)
- [Runtime Contracts](./public-api/runtime-contracts.md)
- [Feature Surfaces](./public-api/feature-surfaces.md)
- [FFI & Rust](./public-api/ffi-and-rust.md)
- [Symbol Inventory（自动生成）](./public-api/_generated/public-symbol-inventory.md)

## 归档

已过时的文档移至 [archive/](./archive/)。

---

维护约定：与当前主线不匹配的文档应及时更新或移至 archive。新增架构文档应在此 README 中注册。
