import os

path = '/Users/shenlan/workspaces/cloud-neutral-toolkit/xworkmate-bridge/docs/internal-reference.md'
with open(path, 'r') as f:
    content = f.read()

content = content.replace(
    '### 包职责\n\nAPP-facing bridge 主控面。',
    '### 包职责\n\nAPP-facing bridge 主控面。该模块已全面切换至 **JSON-RPC 2.0** 作为默认协议。'
)

content = content.replace(
    '- `func ResultEnvelope(id any, result map[string]any) map[string]any`',
    '- `func ResultEnvelope(id any, result map[string]any) map[string]any` (已升级为混合模式，支持 JSON-RPC 2.0 规范同时兼顾 legacy APP 字段)'
)
content = content.replace(
    '- `func ErrorEnvelope(id any, code int, message string) map[string]any`',
    '- `func ErrorEnvelope(id any, code int, message string) map[string]any` (已升级为混合模式，确保 401 等错误能以 JSON 格式被 legacy APP 解析)'
)

with open(path, 'w') as f:
    f.write(content)
