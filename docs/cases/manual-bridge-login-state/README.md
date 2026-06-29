# 手动 Bridge 登录状态误判 Case

## 目标

验证用户未登录 `svc.plus`、但已经保存有效手动 Bridge 配置时，任务线程应使用手动 Bridge，不应显示“请先登录 svc.plus”或因此阻止发送消息。

## 当前状态

- 状态：已定位并完成最小修复，待设计评估和 UI 手动验收。
- 影响范围：桌面端任务线程连接状态、顶部连接标签、发送消息前的连接守卫。
- 不涉及：账号登录协议、Token 存储格式、Bridge ACP 请求协议。

## 问题现象

1. 在 `Settings -> Integrations` 选择“手动 Bridge”。
2. 填写 Bridge URL 和 Token 并保存。
3. 设置页显示“手动 Bridge / 已保存”。
4. 返回任务线程后，顶部仍显示“已退出登录 · 请先登录 svc.plus”。
5. 发送消息时同样被“请先登录 svc.plus”拦截。

## 根因

`resolveGatewayThreadConnectionStateInternal()` 原先在判断手动 Bridge 是否已配置、是否正在发现能力之前，先检查 `accountSignedIn`：

```dart
if (!accountSignedIn) {
  return signedOut;
}
```

因此在下面这个合法状态中，账号分支错误覆盖了 Bridge 分支：

```text
accountSignedIn = false
bridgeConfigured = true
bridgeReady = false
```

手动 Bridge 与 `svc.plus` 托管账号是两种独立连接来源。只有没有任何可用 Bridge 配置时，未登录账号才应产生 `请先登录 svc.plus` 提示。

## 相关调用链

```text
任务线程状态 / 发送消息
  -> assistantConnectionStateForSession()
  -> isBridgeAcpRuntimeConfiguredInternal()
  -> bridgeCapabilityReadyForExecutionTargetInternal()
  -> resolveGatewayThreadConnectionStateInternal()
  -> 已连接 / 正在发现 / 连接失败 / 请先登录
```

关键代码：

| 文件 | 函数 | 职责 |
| --- | --- | --- |
| `lib/app/app_controller_desktop_thread_sessions.dart` | `assistantConnectionStateForSession()` | 汇总账号、Bridge 配置和 capability 状态。 |
| `lib/app/app_controller_desktop_thread_sessions.dart` | `resolveGatewayThreadConnectionStateInternal()` | 生成任务线程最终连接状态和 UI 文案。 |
| `lib/app/app_controller_desktop_runtime_helpers.dart` | `resolveBridgeAcpEndpointInternal()` | 在托管和手动配置之间解析 Bridge Endpoint。 |
| `lib/app/app_controller_desktop_runtime_helpers.dart` | `isBridgeAcpRuntimeConfiguredInternal()` | 判断当前是否存在可运行的 Bridge 配置。 |
| `lib/app/app_controller_desktop_thread_actions.dart` | `dispatchGatewayChatTurnInternal()` | 发送前刷新 capability，并按连接状态决定是否拦截。 |
| `lib/runtime/runtime_controllers_settings_account_impl.dart` | `resolveAcpBridgeServerEffectiveConfigInternal()` | 解析当前有效配置来源：cloud、bridge 或 default。 |
| `lib/runtime/runtime_controllers_settings_account_impl.dart` | `buildSavedAccountProfileSettingsInternal()` | 校验并保存手动 Bridge URL 和 Token 引用。 |

## 当前最小修复

连接状态决策调整为：

```dart
if (!accountSignedIn && !bridgeConfigured) {
  return signedOut;
}
```

账号同步错误只在确实存在账号会话时参与状态决策：

```dart
if (accountSignedIn && (tokenMissing || failed || blocked)) {
  return accountSyncError;
}
```

预期状态矩阵：

| 账号登录 | Bridge 配置 | Bridge Ready | 预期状态 |
| --- | --- | --- | --- |
| 否 | 否 | 否 | `已退出登录 / 请先登录 svc.plus` |
| 否 | 手动 | 否，尚未发现 | `正在发现 / 正在加载 Bridge 能力...` |
| 否 | 手动 | 否，发现失败 | 显示实际 Bridge capability/连接错误 |
| 否 | 手动 | 是 | `已连接 / <手动 Bridge Host>` |
| 是 | 托管 | 否，Token 缺失 | `缺少令牌 / xworkmate-bridge 授权不可用` |
| 是 | 托管 | 是 | `已连接 / xworkmate-bridge.svc.plus` |

## 自动化覆盖

测试文件：`test/features/assistant/assistant_connection_status_test.dart`

新增覆盖：

- `manual bridge discovery does not require a svc.plus account session`
- `manual bridge discovery failure is shown while signed out`

同时保留原有覆盖，确认没有 Bridge 配置且未登录时仍提示登录。

已执行：

```bash
flutter test \
  test/features/assistant/assistant_connection_status_test.dart \
  test/runtime/assistant_connection_state_test.dart \
  test/runtime/assistant_execution_target_test.dart
```

结果：`101` 个测试全部通过。

## 手动验收

### `MANUAL-BRIDGE-LOGIN-001` 未登录账号使用本地 Bridge

前置条件：

- 退出 `svc.plus` 账号。
- 本地 Bridge 正常运行。
- 准备有效的测试 Token，文档中不记录明文。

步骤：

1. 打开 `Settings -> Integrations -> 手动 Bridge`。
2. 输入 `http://127.0.0.1:<port>` 和有效 Token。
3. 保存并返回任务线程。
4. 等待 capability 刷新完成。
5. 选择 Gateway/OpenClaw 并发送一条简单消息。

验收标准：

- 不显示“请先登录 svc.plus”。
- capability 刷新期间显示“正在加载 Bridge 能力...”。
- Bridge 可用时显示已连接，并允许发送消息。
- Bridge 不可用时显示真实连接错误，不退化为账号登录提示。

### `MANUAL-BRIDGE-LOGIN-002` 未配置 Bridge 且未登录

1. 退出账号并清除手动 Bridge 配置。
2. 返回任务线程并尝试发送消息。

验收标准：

- 继续显示“已退出登录 / 请先登录 svc.plus”。
- 不尝试向默认托管 Bridge 发送未授权请求。

### `MANUAL-BRIDGE-LOGIN-003` 托管账号回归

1. 清除手动 Bridge 配置。
2. 登录 `svc.plus` 并完成托管配置同步。
3. 返回任务线程并发送消息。

验收标准：

- 托管 Bridge Ready 时正常连接。
- Token 缺失或同步 blocked 时继续显示专用账号同步错误。

## 待设计评估

1. 是否引入明确的连接来源枚举，例如 `managedCloud`、`manualBridge`、`environment`、`none`，避免通过多个布尔值间接推断。
2. 账号退出后 `AccountSyncState` 是否可能残留，以及是否应在状态模型层主动清除。
3. 手动 Bridge 和托管 Bridge 同时有效时，当前“托管优先”是否符合产品预期。
4. UI 状态和发送守卫是否应统一依赖单一 `BridgeConnectionState`，避免状态分叉。
5. 是否增加完整集成测试：保存手动 Bridge -> 未登录账号 -> capability 刷新 -> 成功发送消息。

