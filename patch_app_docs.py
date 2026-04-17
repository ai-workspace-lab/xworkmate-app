import os

path = '/Users/shenlan/workspaces/cloud-neutral-toolkit/xworkmate-app/docs/architecture/xworkmate-bridge-migration.md'
with open(path, 'r') as f:
    content = f.read()

protocol_section = '''
## Communication Protocol

- **Standard**: 全面转向 **JSON-RPC 2.0** 作为 APP 与 Bridge 之间的默认通信协议。
- **Client Implementation**: `GatewayAcpClient` 与 `GatewayRuntime` 已完成健壮性升级，支持自动识别 JSON-RPC 2.0 报文。
- **Compatibility**: 当前处于混合过渡期，Bridge 响应报文会同时包含 JSON-RPC 2.0 字段（`result`/`error`）与 Legacy 字段（`ok`/`type`/`payload`），确保旧版逻辑不会崩溃。
'''

content += protocol_section

with open(path, 'w') as f:
    f.write(content)
