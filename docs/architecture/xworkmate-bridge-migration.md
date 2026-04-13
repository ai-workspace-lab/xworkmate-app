# XWorkmate Bridge Migration

Last Updated: 2026-04-13

## Summary

`xworkmate-app` 已不再承载内嵌 Go bridge 实现；bridge runtime、ACP forwarding、gateway runtime 与 upstream routing 的主设计都已经迁移到独立 sibling repo：

- repo: `/Users/shenlan/workspaces/cloud-neutral-toolkit/xworkmate-bridge`

这个迁移不是兼容壳，而是当前真实的 cross-repo runtime contract。

## Current Repo Split

### xworkmate-app Owns

- `assistant + settings` 双端 surface
- feature flags、shell、registry、navigation
- app controller、本地状态编排、secure storage 消费
- bridge contract client：`GoTaskService`、`GatewayAcpClient`、`ExternalCodeAgentAcpDesktopTransport`

### xworkmate-bridge Owns

- ACP entrypoints 与 forwarding topology
- provider catalog、routing resolve、gateway runtime
- upstream ACP adapter / gateway adapter
- internal service auth injection 与 bridge-owned routing truth

## Canonical Cross-Repo Docs

建议按下面顺序阅读当前主链文档：

1. app surface inventory
   - [XWorkmate Core Module Inventory](/Users/shenlan/workspaces/cloud-neutral-toolkit/xworkmate-app/docs/architecture/xworkmate-core-module-inventory-2026-04-13.md)
2. app control-plane view
   - [Task Control Plane Unification](/Users/shenlan/workspaces/cloud-neutral-toolkit/xworkmate-app/docs/architecture/task-control-plane-unification.md)
3. bridge forwarding view
   - [ACP Forwarding Topology](/Users/shenlan/workspaces/cloud-neutral-toolkit/xworkmate-bridge/docs/architecture/acp-forwarding-topology.md)
4. bridge entrypoint ADR
   - [ADR: Unified Bridge Entry Points](/Users/shenlan/workspaces/cloud-neutral-toolkit/xworkmate-bridge/docs/architecture/adr-unified-bridge-entrypoints.md)

## Build Contract

`xworkmate-app` 仍然消费名为 `xworkmate-go-core` 的 helper artifact。

这表示：

- helper 从 `xworkmate-bridge` 构建
- app 负责定位与调用 helper
- helper 内部的 bridge/runtime 行为以 bridge repo 为准，不再在 app repo 内保留并列设计文档

## Operational Note

- 本地开发默认要求 `xworkmate-app` 与 `xworkmate-bridge` 以 sibling repo 形式存在
- 若目录布局不同，可通过 `XWORKMATE_BRIDGE_DIR` 显式指定 bridge 仓库位置
- app 端只消费 bridge capability、routing、gateway runtime 合同，不再在本地恢复旧 provider/module 真源
