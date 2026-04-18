import os

path = '/Users/shenlan/workspaces/cloud-neutral-toolkit/xworkmate-bridge/.github/workflows/pipeline.yml'
with open(path, 'r') as f:
    content = f.read()

# Redirect all xworkmate-bridge.svc.plus calls to the functional xworkmate-bridge.svc.plus sub-paths
content = content.replace(
    'https://xworkmate-bridge.svc.plus/codex/acp/rpc',
    'https://xworkmate-bridge.svc.plus/acp-server/codex/acp/rpc'
)
content = content.replace(
    'https://xworkmate-bridge.svc.plus/opencode/acp/rpc',
    'https://xworkmate-bridge.svc.plus/acp-server/opencode/acp/rpc'
)
content = content.replace(
    'https://xworkmate-bridge.svc.plus/gemini/acp/rpc',
    'https://xworkmate-bridge.svc.plus/acp-server/gemini/acp/rpc'
)

with open(path, 'w') as f:
    f.write(content)
