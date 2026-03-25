# External ACP Server

一个独立的 Agent Communication Protocol (ACP) 服务实现，支持：
- **Single-agent 模式**: 单代理执行
- **Multi-agent 模式**: 多代理协作
- **自定义工具**: 扩展 MCP 工具能力

## 架构

```
┌─────────────────────────────────────────────────────┐
│                    ACP Server                        │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  │
│  │ WebSocket   │  │ HTTP POST   │  │ Tool Bridge │  │
│  │  /acp       │  │ /acp/rpc    │  │  (MCP)      │  │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘  │
│         │                │                │          │
│         └────────────────┴────────────────┘          │
│                          │                           │
│                   ┌──────▼──────┐                    │
│                   │   Router    │                    │
│                   └──────┬──────┘                    │
│                          │                           │
│         ┌────────────────┼────────────────┐         │
│         │                │                │         │
│   ┌─────▼─────┐   ┌─────▼─────┐   ┌─────▼─────┐    │
│   │  Session  │   │   Agent   │   │   Tool    │    │
│   │  Manager  │   │  Executor │   │  Handler  │    │
│   └───────────┘   └───────────┘   └───────────┘    │
└─────────────────────────────────────────────────────┘
```

## 快速开始

```bash
# 安装依赖
pip install -r requirements.txt

# 配置环境变量
export ACP_LISTEN_ADDR="127.0.0.1:8787"
export ACP_MULTI_AGENT_ENABLED="true"

# 启动服务
python server.py serve

# 或使用自定义配置
python server.py serve --listen 0.0.0.0:9000
```

## 环境变量

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `ACP_LISTEN_ADDR` | `127.0.0.1:8787` | 服务监听地址 |
| `ACP_MULTI_AGENT_ENABLED` | `true` | 是否启用多代理模式 |
| `ACP_MULTI_AGENT_MODEL` | `gpt-4o` | 多代理使用的模型 |

## 协议

### JSON-RPC 方法

| 方法 | 说明 |
|------|------|
| `acp.capabilities` | 查询服务器能力 |
| `session.start` | 启动新会话 |
| `session.message` | 发送消息（延续会话）|
| `session.cancel` | 取消会话 |
| `session.close` | 关闭会话 |

### 通知类型

| type | 说明 |
|------|------|
| `status` | 会话状态变更 |
| `delta` | 增量文本输出 |
| `step` | 多代理步骤进度 |

## 扩展自定义工具

在 `tools/` 目录下添加新的工具实现：

```python
# tools/my_tool.py
class MyTool:
    name = "my_tool"
    description = "工具描述"
    input_schema = {
        "type": "object",
        "properties": {
            "input": {"type": "string", "description": "输入参数"}
        },
        "required": ["input"]
    }

    def execute(self, arguments: dict) -> str:
        return f"处理结果: {arguments.get('input')}"
```

在 `server.py` 中注册：

```python
from tools.my_tool import MyTool

tool_registry.register(MyTool())
```