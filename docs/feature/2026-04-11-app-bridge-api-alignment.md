# APP 侧对齐当前 xworkmate-bridge API

本轮 APP 侧对接以当前 `xworkmate-bridge` 实际返回为准，不再额外定义前端私有 contract。

## 当前后端事实

- `acp.capabilities` 当前继续返回：
  - `singleAgent`
  - `multiAgent`
  - `providerCatalog`
  - `gatewayProviders`
- `xworkmate.routing.resolve` 当前继续返回：
  - `resolvedExecutionTarget`
  - `resolvedEndpointTarget`
  - `resolvedProviderId`
  - `resolvedGatewayProviderId`
- `session.start` / `session.message` 当前请求仍消费线程级 `workingDirectory`
- 当前 bridge 还没有项目列表接口

## APP 侧执行约定

- APP 模式选择入口只暴露：
  - `single-agent`
  - `gateway`
- `multi-agent` 仍作为 bridge 可返回状态被解析和展示，但不再作为用户主动选择入口
- 线程级“项目选择”当前直接等价于 bridge 请求里的 `workingDirectory`
- `workingDirectory` 与本地 `workspaceBinding` 分离：
  - `workingDirectory`: 发给 bridge 的执行目录
  - `workspaceBinding`: APP 本地 artifact 回写目录

## 当前实现结果

- 每个线程持久化 `selectedWorkingDirectory`
- `single-agent` 与 `gateway` 都复用同一个线程级 `selectedWorkingDirectory`
- follow-up 请求继续沿用：
  - `sessionId == threadId == sessionKey`
  - 同一线程绑定的 `workingDirectory`
- 若线程没有选项目目录，APP 会阻断发送并提示先选择项目

## 兼容策略

- 继续解析 `resolvedEndpointTarget`，但它不再作为前端主状态来源
- 继续解析 `multiAgent`，但不提供手动切换入口
- `providerCatalog` 继续驱动 single-agent provider picker
- `gatewayProviders` 继续按 bridge 返回结构保存和消费，不在 APP 侧硬编码扩展
