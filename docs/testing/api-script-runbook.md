# 外部服务 API 脚本运行说明

Last Updated: 2026-04-22

本文说明 `xworkmate-app` 里两份外部服务 API 测试脚本的用途、执行方式和适用边界。

## 1. 脚本列表

### 1.1 API 接口测试脚本

- [`scripts/ci/verify_api_interface_contract.sh`](/Users/shenlan/workspaces/cloud-neutral-toolkit/xworkmate-app/scripts/ci/verify_api_interface_contract.sh)

用途：

- 校验账户服务与 bridge 主入口的接口契约
- 重点验证请求路径、鉴权头、返回结构和能力面数据

### 1.2 场景测试脚本

- [`scripts/ci/verify_api_scenario_contract.sh`](/Users/shenlan/workspaces/cloud-neutral-toolkit/xworkmate-app/scripts/ci/verify_api_scenario_contract.sh)

用途：

- 按真实使用链路跑完整场景
- 重点验证登录 -> 同步 -> 能力 -> 路由 -> 会话启动 / 续跑 / 取消 / 关闭

## 2. 运行前提

两份脚本都依赖以下环境变量：

- `REVIEW_ACCOUNT_LOGIN_PASSWORD`
- 可选 `BRIDGE_AUTH_TOKEN`，未提供时使用 profile sync 返回的 token
- 可选 `BRIDGE_SERVER_URL`
- 可选 `BRIDGE_SERVER_URLS`，用于接口脚本同时验证多个 bridge host
- 可选 `REVIEW_ACCOUNT_BASE_URL`

凭据从本地 `.env`（已 gitignore）或 secret store 注入，**不要把明文密码/Token 写进文档或命令历史**。先准备 `.env`（参考仓库根目录 `.env.example`），再 `source` 后运行：

```bash
set -a; source .env; set +a   # 载入 REVIEW_ACCOUNT_LOGIN_PASSWORD / BRIDGE_AUTH_TOKEN 等
bash scripts/ci/verify_api_interface_contract.sh
```

如需单条命令显式注入，使用变量引用而非明文：

```bash
REVIEW_ACCOUNT_LOGIN_PASSWORD="$REVIEW_ACCOUNT_LOGIN_PASSWORD" \
BRIDGE_AUTH_TOKEN="$BRIDGE_AUTH_TOKEN" \
BRIDGE_SERVER_URL='https://xworkmate-bridge.svc.plus' \
bash scripts/ci/verify_api_interface_contract.sh
```

双入口验证示例：

```bash
REVIEW_ACCOUNT_LOGIN_PASSWORD="$REVIEW_ACCOUNT_LOGIN_PASSWORD" \
BRIDGE_SERVER_URLS='https://xworkmate-bridge.svc.plus,https://cn-xworkmate-bridge.svc.plus' \
bash scripts/ci/verify_api_interface_contract.sh
```

## 3. 默认校验入口

推荐使用 `Makefile` 目标：

```bash
make test-api-contract
make test-api-scenario-contract
```

如果需要一次性执行两份脚本，可使用：

```bash
make check-api-external
```

## 4. 脚本覆盖内容

### 4.1 `test-api-contract`

- `POST /api/auth/login`
- `GET /api/auth/session`
- `GET /api/auth/xworkmate/profile/sync`
- `GET /api/ping`
- `POST /acp/rpc` with `acp.capabilities`
- `POST /acp/rpc` with `xworkmate.routing.resolve`

### 4.2 `test-api-scenario-contract`

- 登录与会话确认
- profile sync 元数据读取
- bridge capabilities 拉取
- routing resolve
- `session.start`
- `session.message`
- `session.cancel`
- `session.close`

## 5. 已知行为

- `session.start` / `session.message` 在当前环境下可能返回下游连接失败，这不代表脚本失效
- 只要脚本正确拿到 JSON-RPC 返回并解析出结果，就认为脚本可用
- 脚本不会把 `BRIDGE_SERVER_URL` 当成 runtime 真源；它只作为可选显式输入

## 6. 相关文档

- [APP 对接外部服务 API 接口测试详细清单](./app-external-service-api-test-matrix.md)
- [XWorkmate 测试规范模板与指南](./xworkmate-test-spec.md)
- [测试 Case 覆盖矩阵](./test-case-coverage-matrix.md)
