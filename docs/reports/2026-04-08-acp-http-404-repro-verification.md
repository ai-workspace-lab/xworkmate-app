# ACP HTTP 404 场景自动复现验证

## 变更摘要

本次验证目标不是再次修复，而是确认 `ACP_HTTP_404: ACP HTTP request failed (404) · unexpected content type: text/plain` 这一类场景能否通过自动化测试稳定复现，并作为后续回归证据保留。

验证对象聚焦在 ACP runtime transport 行为：

- 当客户端以 `http(s)` 基址优先请求 `/acp/rpc`
- 服务端返回 `404`
- 且 `content-type` 为 `text/plain`
- 但同一基址下 `/acp` WebSocket 仍可正常响应

该场景现在由 `test/runtime/gateway_acp_client_suite.dart` 内的专门用例覆盖。

## 测试命令与结果

- `flutter test test/runtime/gateway_acp_client_test.dart --reporter expanded --plain-name "falls back to websocket when HTTP bridge returns plain-text 404"`
  - 结果：通过
  - 关键输出：`GatewayAcpClient falls back to websocket when HTTP bridge returns plain-text 404`
- `flutter test test/runtime/gateway_acp_client_test.dart --reporter expanded`
  - 结果：通过
  - 关键输出：`00:00 +12: All tests passed!`
- `flutter analyze`
  - 结果：通过
  - 关键输出：`No issues found!`

## 重点验证点覆盖

- 已验证：自动化测试可以稳定构造“`/acp/rpc` 返回 `404 text/plain`，但 `/acp` WebSocket 可用”的复现场景。
- 已验证：当前实现会在该场景下从 HTTP bridge 失败回退到 WebSocket，并成功获取 ACP capabilities。
- 已验证：原有错误分类仍保留，`text/html` 这类网页响应不会被误判为可回退场景。
- 已验证：相关 ACP client suite 全量回归通过，没有引入同文件内的其他协议回归。

## 失败项

- 无自动化失败项。

## 高风险回归点

- ACP transport 是运行时核心链路，涉及 HTTP / WebSocket 双通道切换，属于中高风险协议行为。
- 当前自动化复现基于 fake server，覆盖的是协议级场景，不等同于已经对用户机器上的真实 `127.0.0.1:18789` 服务完成实机重放。

## 建议人工补测项

- 如果需要证明“截图里的真实本地服务”与自动化场景完全一致，建议对用户当前本地 gateway 做一次实机补测：
  - 在真实 `127.0.0.1:18789` 上确认 `/acp/rpc` 是否返回 `404 text/plain`
  - 同时确认 `/acp` WebSocket 是否可握手并返回 `acp.capabilities`
  - 从 Desktop UI 发起一次与截图相同的对话请求，确认不再出现该报错

## 相关文件

- `test/runtime/gateway_acp_client_suite.dart`
- `test/runtime/gateway_acp_client_test.dart`
- `lib/runtime/gateway_acp_client.dart`
