# APP 侧对齐当前 xworkmate-bridge API

Last Updated: 2026-04-14

本文件只记录当前 `xworkmate-app` 实际消费的 bridge 合同口径，不再延续旧的 `single-agent provider picker` 叙述。

## 当前后端事实

- `acp.capabilities` 当前 app 主链消费的核心字段是：
  - `availableExecutionTargets`
  - `providerCatalog`
  - `gatewayProviders`
- 其中：
  - `providerCatalog` 对应 `agent` 目标下的 ACP server bridges
  - `gatewayProviders` 对应 `gateway` 目标下的 gateway provider 列表
- `singleAgent` / `multiAgent` 仍可能作为兼容元数据被解析，但它们不再定义任务对话框的主术语与主状态

## APP 侧执行约定

- APP 任务对话模式只暴露：
  - `agent`
  - `gateway`
- provider picker 按 target-scoped catalog 渲染：
  - `agent` catalog 只消费 bridge 返回的 ACP bridge providers
  - `gateway` catalog 只消费 bridge 返回的 gateway providers；当前为 `openclaw`，未来可扩展 `hermes`
- APP 不再维护静态 provider 列表，也不从线程历史值反向生成 catalog

## 当前实现结果

- 每个线程持久化：
  - `executionTarget`
  - `providerId`
  - `selectedWorkingDirectory`
- `agent` 与 `gateway` 都复用同一个线程级 `selectedWorkingDirectory`
- provider 选择主链统一为：
  - `providerCatalogForExecutionTarget(...)`
  - `resolveProviderForExecutionTarget(...)`
  - `setAssistantProvider(...)`
- 渲染态读取统一通过：
  - `assistantProviderForSession(sessionKey)`

## 当前兼容边界

- transport / capability parser 可以继续兼容解析 `single-agent` 旧字段值
- 这种兼容只存在于低层解析，不再抬升为 UI 文案、架构主术语或设计文档口径
- gateway provider 若 bridge 当前未广告，APP 显示为空或禁用，不再伪造 `openclaw` 默认入口

## See Also

- [Task Dialog Provider Selection Mainline](/Users/shenlan/workspaces/cloud-neutral-toolkit/xworkmate-app/docs/architecture/task-dialog-provider-selection-mainline.md)
- [Task Control Plane Unification](/Users/shenlan/workspaces/cloud-neutral-toolkit/xworkmate-app/docs/architecture/task-control-plane-unification.md)
