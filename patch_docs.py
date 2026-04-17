import os

path = '/Users/shenlan/workspaces/cloud-neutral-toolkit/xworkmate-bridge/docs/api-reference.md'
with open(path, 'r') as f:
    content = f.read()

content = content.replace(
    'HTTP 与 WebSocket 统一使用 JSON-RPC 2.0 结构：',
    'HTTP 与 WebSocket 统一使用 **JSON-RPC 2.0** 作为默认通信协议。为了兼容旧版 XWorkmate APP，所有的响应报文均采用混合模式（Hybrid Mode），同时包含 JSON-RPC 2.0 字段与 legacy 扩展字段：'
)

new_rpc_example = '''成功响应：

```json
{
  "jsonrpc": "2.0",
  "id": "req-1",
  "result": {
    "success": true,
    "output": "..."
  },
  "ok": true,
  "type": "res",
  "payload": {
    "success": true,
    "output": "..."
  },
  "seq": 0
}
```

错误响应：

```json
{
  "jsonrpc": "2.0",
  "id": "req-1",
  "error": {
    "code": -32601,
    "message": "unknown method: ..."
  },
  "ok": false,
  "type": "res",
  "payload": null,
  "seq": 0
}
```'''

content = content.replace('成功响应：\n\n```json\n{\n  "jsonrpc": "2.0",\n  "id": "req-1",\n  "result": {}\n}\n```', new_rpc_example)
content = content.replace('错误响应：\n\n```json\n{\n  "jsonrpc": "2.0",\n  "id": "req-1",\n  "error": {\n    "code": -32601,\n    "message": "unknown method: ..."\n  }\n}\n```', '')

content = content.replace(
    '- 与 `session.start` 相同；bridge 会复用 session 历史，尤其在 multi-agent 与 Gemini adapter 路径中。',
    '- 与 `session.start` 相同；bridge 会复用 session 历史（历史记录会以 `USER: ` 和 `ASSISTANT: ` 前缀进行上下文包裹），尤其在 multi-agent 与 Gemini adapter 路径中。'
)

with open(path, 'w') as f:
    f.write(content)
