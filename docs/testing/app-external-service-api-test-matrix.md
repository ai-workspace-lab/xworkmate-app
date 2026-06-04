# APP 对接外部服务 API 接口测试详细清单

Last Updated: 2026-04-22

本文记录 `xworkmate-app` 当前对外部服务的 APP 侧接口对接清单，重点覆盖：

- 账户服务 `accounts.svc.plus`
- 桥接服务 `xworkmate-bridge.svc.plus`
- 桥接侧 JSON-RPC 会话接口 `session.start` / `session.message` / `session.cancel` / `session.close`

本文目标不是抽象协议说明，而是把 APP 真实会调用的接口、请求体、返回体、鉴权方式、已验证结果和当前风险点整理成可执行测试清单。

## 1. 范围与用途

### 1.1 涵盖范围

- 账户登录与会话查询
- 账户同步返回的 bridge 元数据
- bridge 主入口 `/acp/rpc`
- `acp.capabilities`
- `xworkmate.routing.resolve`
- 会话生命周期接口：
  - `session.start`
  - `session.message`
  - `session.cancel`
  - `session.close`

### 1.2 不涵盖范围

- UI 视觉样式
- 纯本地文件系统工具
- 账户注册、找回密码、管理后台页面
- bridge 后端内部 `/acp-server/*` / `/gateway/*` 私有映射细节

### 1.3 适用场景

- Apple 审核只读账号连通性确认
- APP 上线前外部依赖冒烟
- bridge 协议改动后的回归核验
- 安全边界确认：
  - `BRIDGE_AUTH_TOKEN` 是否只作为 Bearer token 使用
  - `BRIDGE_SERVER_URL` 是否仅作为元数据
  - 会话接口是否按当前 bridge contract 统一选择 `/acp/rpc`，并用 routing metadata 表达 OpenClaw gateway 目标

## 2. 统一测试前提

### 2.1 环境变量 / 外部参数

- `BRIDGE_SERVER_URL=https://xworkmate-bridge.svc.plus`
- `BRIDGE_AUTH_TOKEN=<managed bridge token>`

### 2.2 账户信息

- `url`: `https://accounts.svc.plus`
- `login_name`: `review@svc.plus`
- `login_password`: `***REMOVED-CREDENTIAL***`

### 2.3 鉴权规则

- 账户接口使用账户登录返回的 session token
- bridge 接口使用 `Authorization: Bearer <BRIDGE_AUTH_TOKEN>`
- 不允许用 gateway profile token 代替 bridge token
- 不允许把 `BRIDGE_SERVER_URL` 当作 runtime 入口真源

### 2.4 当前代码侧入口

- [`lib/runtime/account_runtime_client.dart`](/Users/shenlan/workspaces/cloud-neutral-toolkit/xworkmate-app/lib/runtime/account_runtime_client.dart)
- [`lib/runtime/gateway_acp_client.dart`](/Users/shenlan/workspaces/cloud-neutral-toolkit/xworkmate-app/lib/runtime/gateway_acp_client.dart)
- [`lib/runtime/go_task_service_client.dart`](/Users/shenlan/workspaces/cloud-neutral-toolkit/xworkmate-app/lib/runtime/go_task_service_client.dart)
- [`lib/runtime/external_code_agent_acp_desktop_transport.dart`](/Users/shenlan/workspaces/cloud-neutral-toolkit/xworkmate-app/lib/runtime/external_code_agent_acp_desktop_transport.dart)

## 3. 接口总览

| 服务 | 方法 / 路径 | HTTP 方法 | 鉴权 | 当前用途 | 备注 |
| --- | --- | --- | --- | --- | --- |
| accounts | `/api/auth/login` | `POST` | 无 | 登录并拿 session token | Apple 审核只读账号使用 |
| accounts | `/api/auth/session` | `GET` | `Authorization: Bearer <session token>` | 获取当前会话和用户信息 | APP 端登录态校验 |
| accounts | `/api/auth/xworkmate/profile/sync` | `GET` | `Authorization: Bearer <session token>` | 拉取 bridge 同步元数据 | 返回 `BRIDGE_SERVER_URL` / `BRIDGE_AUTH_TOKEN` |
| bridge | `/acp/rpc` | `POST` | `Authorization: Bearer <BRIDGE_AUTH_TOKEN>` | bridge JSON-RPC 主入口 | capabilities、routing、agent 任务、OpenClaw gateway 任务、cancel、close |
| bridge | `acp.capabilities` | JSON-RPC method | 同上 | 拉取 provider catalog / target catalog | capability 只读快照 |
| bridge | `xworkmate.routing.resolve` | JSON-RPC method | 同上 | 解析 provider / gateway / skills 路由 | 返回 resolved / unavailable 信息 |
| bridge | `session.start` | JSON-RPC method | 同上 | 开启新会话 | session 生命周期起点 |
| bridge | `session.message` | JSON-RPC method | 同上 | 继续现有会话 | 续写 / follow-up |
| bridge | `session.cancel` | JSON-RPC method | 同上 | 取消正在进行的会话 | 终止流式任务 |
| bridge | `session.close` | JSON-RPC method | 同上 | 关闭会话 | 释放会话资源 |

## 4. 账户服务测试清单

### 4.1 `POST /api/auth/login`

#### 目标

- 验证只读审核账号可以正常登录
- 验证账户服务返回 session token

#### 请求

```json
{
  "identifier": "review@svc.plus",
  "password": "***REMOVED-CREDENTIAL***"
}
```

#### 期望返回

- HTTP `200`
- 响应体包含：
  - `access_token`
  - `token`
  - `expiresAt`
  - `user`
  - `mfaRequired` / `mfa_required`

#### 当前实测结果

- 已通过
- 返回 `200`
- 返回体包含用户 `readonly` 角色与会话 token

#### 关键断言

- 不应返回 MFA 挑战
- 不应要求额外二次登录
- token 不应写入普通 settings

### 4.2 `GET /api/auth/session`

#### 目标

- 校验登录 token 是否可用于读取当前会话
- 校验用户信息、角色、权限是否可见

#### 请求

- Header: `Authorization: Bearer <session token>`

#### 期望返回

- HTTP `200`
- `user.email`
- `user.username`
- `user.role`
- `user.permissions`
- `user.tenants` 或等价租户信息

#### 当前实测结果

- 已通过
- 返回 `200`
- 能读取会话和权限

#### 关键断言

- 不能依赖 bridge token
- 不能读取旧的 managed secret 代替 session token

### 4.3 `GET /api/auth/xworkmate/profile/sync`

#### 目标

- 读取 bridge 同步元数据
- 确认 APP 只把 `BRIDGE_SERVER_URL` 作为 metadata
- 确认 `BRIDGE_AUTH_TOKEN` 能被同步回 APP 侧 secure storage

#### 请求

- Header: `Authorization: Bearer <session token>`

#### 期望返回

- HTTP `200`
- 响应体包含：
  - `BRIDGE_SERVER_URL`
  - `BRIDGE_AUTH_TOKEN`

#### 当前实测结果

- 已通过
- 返回：
  - `BRIDGE_SERVER_URL=https://xworkmate-bridge.svc.plus`
  - `BRIDGE_AUTH_TOKEN=<managed bridge token>`

#### 关键断言

- `BRIDGE_SERVER_URL` 只作为同步元数据，不参与 runtime endpoint 选择
- `BRIDGE_AUTH_TOKEN` 只进入 secure storage / managed secret

## 5. 桥接主入口测试清单

### 5.1 `POST /acp/rpc`

#### 目标

- 验证 bridge 主入口可连通
- 验证鉴权头正确
- 验证 JSON-RPC 协议错误返回格式

#### 请求

- Header: `Authorization: Bearer <BRIDGE_AUTH_TOKEN>`
- Header: `Content-Type: application/json`
- Body: JSON-RPC payload

#### 期望返回

- HTTP `200` 或 JSON-RPC 协议级错误
- 响应体为 JSON-RPC 风格：
  - `jsonrpc`
  - `id`
  - `ok`
  - `result`
  - `error`

#### 当前实测结果

- 发送空对象会返回协议错误：
  - `missing method`
- 说明服务在线，入口正确

#### 关键断言

- 不应走 `/acp-server/*`
- 不应走 `/gateway/*`
- 不应回退到本地 loopback 作为 runtime 主入口

### 5.2 `acp.capabilities`

#### 请求体

```json
{
  "jsonrpc": "2.0",
  "id": "1",
  "method": "acp.capabilities",
  "params": {}
}
```

#### 返回体重点

- `availableExecutionTargets`
- `providerCatalog`
- `gatewayProviders`
- `singleAgent`
- `capabilities`

#### 当前实测结果

- `availableExecutionTargets`: `agent`, `gateway`
- `providerCatalog`:
  - `codex`
  - `opencode`
  - `gemini`
  - `hermes`
- `gatewayProviders`:
  - `openclaw`

#### 关键断言

- `providerCatalog` 只作为 agent 目标 catalog
- `gatewayProviders` 只作为 gateway 目标 catalog
- APP 侧 provider 菜单必须来自这里，不可静态硬编码

### 5.3 `xworkmate.routing.resolve`

#### 请求体

```json
{
  "jsonrpc": "2.0",
  "id": "1",
  "method": "xworkmate.routing.resolve",
  "params": {
    "taskPrompt": "check api",
    "workingDirectory": "/tmp",
    "routing": {
      "routingMode": "auto",
      "preferredGatewayTarget": "codex",
      "explicitExecutionTarget": "agent",
      "explicitProviderId": "codex",
      "explicitModel": "",
      "explicitSkills": [],
      "allowSkillInstall": false,
      "availableSkills": []
    }
  }
}
```

#### 返回体重点

- `resolvedExecutionTarget`
- `resolvedProviderId`
- `resolvedGatewayProviderId`
- `resolvedModel`
- `resolvedSkills`
- `unavailable`
- `unavailableCode`
- `unavailableMessage`

#### 当前实测结果

- `resolvedExecutionTarget`: `single-agent`
- `resolvedProviderId`: `codex`
- `unavailable`: `false`

#### 关键断言

- 路由解析结果必须和 UI / controller 的执行目标一致
- `unavailable` 为真时必须能带出原因字段

## 6. 会话接口测试清单

### 6.1 通用请求模型

桥接侧会话接口都使用 JSON-RPC，且共享同一套会话标识：

- `sessionId`
- `threadId`
- 任务类请求还会带：
  - `mode`
  - `taskPrompt`
  - `workingDirectory`
  - `selectedSkills`
  - `attachments`
  - `provider`
  - `routing`
  - `requestedExecutionTarget`
  - `executionTarget`

这些字段由 [`GoTaskServiceRequest.toExternalAcpParams()`](/Users/shenlan/workspaces/cloud-neutral-toolkit/xworkmate-app/lib/runtime/go_task_service_client.dart) 生成。

### 6.2 `session.start`

#### 目标

- 开启新任务会话
- 验证桥接会话起点是否正确走向下游执行面

#### 最小请求体

```json
{
  "jsonrpc": "2.0",
  "id": "1",
  "method": "session.start",
  "params": {
    "sessionId": "test-session-001",
    "threadId": "test-session-001",
    "mode": "gateway-chat",
    "taskPrompt": "Say hello in one short sentence.",
    "workingDirectory": "/tmp",
    "selectedSkills": [],
    "attachments": [],
    "provider": "codex",
    "routing": {
      "routingMode": "auto",
      "preferredGatewayTarget": "codex",
      "explicitExecutionTarget": "agent",
      "explicitProviderId": "codex",
      "explicitModel": "",
      "explicitSkills": [],
      "allowSkillInstall": false,
      "availableSkills": []
    },
    "requestedExecutionTarget": "agent",
    "executionTarget": "agent"
  }
}
```

#### 返回体重点

- `ok`
- `success`
- `error`
- `mode`
- `provider`
- `resolvedExecutionTarget`
- `resolvedProviderId`
- `resolvedGatewayProviderId`
- `resolvedModel`
- `resolvedSkills`
- `skillResolutionSource`
- `needsSkillInstall`
- `turnId`
- `unavailable`

#### 当前实测结果

- HTTP `200`
- 返回 `success: false`
- 返回错误：
  - `dial tcp 127.0.0.1:9001: connect: connection refused`
- 返回 `resolvedExecutionTarget: single-agent`
- 返回 `resolvedProviderId: codex`
- 返回 `turnId`

#### 结论

- 协议入口正常
- 会话方法可用
- 当前失败点在桥接后端继续转发到本地 `127.0.0.1:9001`

#### 关键断言

- 不能回退到本地 hardcoded endpoint 作为 APP runtime 真源
- 不能把 provider 路由走成 `/acp-server/*` 直连

### 6.3 `session.message`

#### 目标

- 继续已有会话
- 校验 follow-up 是否沿用同一 `sessionId` / `threadId`

#### 最小请求体

```json
{
  "jsonrpc": "2.0",
  "id": "2",
  "method": "session.message",
  "params": {
    "sessionId": "test-session-001",
    "threadId": "test-session-001",
    "mode": "gateway-chat",
    "taskPrompt": "Continue with a very short acknowledgement.",
    "workingDirectory": "/tmp",
    "selectedSkills": [],
    "attachments": [],
    "provider": "codex",
    "routing": {
      "routingMode": "auto",
      "preferredGatewayTarget": "codex",
      "explicitExecutionTarget": "agent",
      "explicitProviderId": "codex",
      "explicitModel": "",
      "explicitSkills": [],
      "allowSkillInstall": false,
      "availableSkills": []
    },
    "requestedExecutionTarget": "agent",
    "executionTarget": "agent"
  }
}
```

#### 返回体重点

- 与 `session.start` 相同的会话结果字段

#### 当前实测结果

- HTTP `200`
- 返回 `success: false`
- 返回错误：
  - `dial tcp 127.0.0.1:9001: connect: connection refused`
- 返回 `turnId`

#### 关键断言

- 续写请求不能改写线程归属
- 续写请求不能偷偷切换到另一个 provider

### 6.4 `session.cancel`

#### 目标

- 取消进行中的会话
- 校验取消接口是否幂等可用

#### 最小请求体

```json
{
  "jsonrpc": "2.0",
  "id": "3",
  "method": "session.cancel",
  "params": {
    "sessionId": "test-session-001",
    "threadId": "test-session-001"
  }
}
```

#### 返回体重点

- `accepted`
- `cancelled`

#### 当前实测结果

- HTTP `200`
- 返回：
  - `accepted: true`
  - `cancelled: false`

#### 关键断言

- 取消接口应可在会话失败后调用
- 不应因会话已失败而返回协议错误

### 6.5 `session.close`

#### 目标

- 关闭会话
- 回收会话资源

#### 最小请求体

```json
{
  "jsonrpc": "2.0",
  "id": "4",
  "method": "session.close",
  "params": {
    "sessionId": "test-session-001",
    "threadId": "test-session-001"
  }
}
```

#### 返回体重点

- `accepted`
- `closed`

#### 当前实测结果

- HTTP `200`
- 返回：
  - `accepted: true`
  - `closed: true`

#### 关键断言

- 会话关闭应始终可调用
- 关闭接口不能依赖会话先成功完成

## 7. 代码到接口的映射

| 代码位置 | 说明 |
| --- | --- |
| [`lib/runtime/account_runtime_client.dart`](/Users/shenlan/workspaces/cloud-neutral-toolkit/xworkmate-app/lib/runtime/account_runtime_client.dart) | 账户登录、会话、同步接口封装 |
| [`lib/runtime/gateway_acp_client.dart`](/Users/shenlan/workspaces/cloud-neutral-toolkit/xworkmate-app/lib/runtime/gateway_acp_client.dart) | bridge JSON-RPC 请求、capabilities、routing、session 生命周期 |
| [`lib/runtime/go_task_service_client.dart`](/Users/shenlan/workspaces/cloud-neutral-toolkit/xworkmate-app/lib/runtime/go_task_service_client.dart) | 会话请求参数组装 |
| [`lib/runtime/external_code_agent_acp_desktop_transport.dart`](/Users/shenlan/workspaces/cloud-neutral-toolkit/xworkmate-app/lib/runtime/external_code_agent_acp_desktop_transport.dart) | session.start / session.message 触发路径 |

## 8. 自动化测试建议

### 8.1 现有自动化基础

- [`test/runtime/gateway_acp_client_auth_test.dart`](/Users/shenlan/workspaces/cloud-neutral-toolkit/xworkmate-app/test/runtime/gateway_acp_client_auth_test.dart)
- [`test/runtime/runtime_controllers_settings_account_test.dart`](/Users/shenlan/workspaces/cloud-neutral-toolkit/xworkmate-app/test/runtime/runtime_controllers_settings_account_test.dart)

### 8.2 推荐新增测试

#### 桥接协议层

- `test/runtime/gateway_acp_client_session_test.dart`
  - 覆盖 `session.start`
  - 覆盖 `session.message`
  - 覆盖 `session.cancel`
  - 覆盖 `session.close`
  - 断言 Bearer 头、JSON-RPC method、params 结构

#### 失败分支

- `session.start` 下游连接失败时，返回值中应保留：
  - `success: false`
  - `error`
  - `turnId`
  - `resolvedProviderId`
- `session.message` follow-up 失败时，不应破坏会话标识

### 8.3 建议断言

- `Authorization` 必须是 `Bearer <token>`
- capability、routing、agent 任务、OpenClaw gateway `session.start` / `session.message`、`session.cancel`、`session.close` 请求路径必须是 `/acp/rpc`
- 不允许出现 `/acp-server/` 直连请求
- 不允许出现 `/gateway/openclaw` app-facing 请求；OpenClaw gateway 目标必须通过 routing metadata 表达
- `session.cancel` / `session.close` 必须接受 `sessionId` + `threadId`
- `BRIDGE_SERVER_URL` 不可参与运行时路径拼接

## 9. 当前已知风险

- `session.start` / `session.message` 当前环境下下游连接到 `127.0.0.1:9001` 失败
- 这说明 bridge 主入口可用，但后端 provider 适配层在当前运行环境里未就绪
- 这是 bridge 后端运行态问题，不是 APP 侧 JSON-RPC 协议错误

## 10. 执行顺序建议

1. `POST /api/auth/login`
2. `GET /api/auth/session`
3. `GET /api/auth/xworkmate/profile/sync`
4. `acp.capabilities`
5. `xworkmate.routing.resolve`
6. `session.start`
7. `session.message`
8. `session.cancel`
9. `session.close`

## 11. 结论

当前 APP 对接外部服务的主链路已经明确：

- 账户侧负责登录与同步元数据
- bridge 侧负责 capability、路由解析和会话生命周期
- capability、routing、agent 任务、OpenClaw gateway 任务、cancel、close 经过 `/acp/rpc`
- OpenClaw `session.start` / `session.message` 通过 `/acp/rpc` routing metadata 表达 gateway/openclaw 目标
- `session.cancel` / `session.close` 的协议入口已验证可用
- 当前剩余风险集中在桥接后端下游 provider 连接，而不是 APP 侧接口拼接
