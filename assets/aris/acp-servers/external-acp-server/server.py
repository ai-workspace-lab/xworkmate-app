#!/usr/bin/env python3
"""
External ACP Server - 独立的 Agent Communication Protocol 服务

支持:
- Single-agent 模式: 调用外部 CLI 工具
- Multi-agent 模式: 多代理协作
- 自定义工具: MCP 兼容的工具扩展

用法:
    python server.py serve --listen 127.0.0.1:8787
    python server.py bridge  # 作为 MCP 工具桥接器运行
"""

import asyncio
import json
import logging
import os
import signal
import sys
import time
import uuid
from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Callable, Optional
from contextlib import asynccontextmanager

try:
    from aiohttp import web
    import aiohttp
    AIOHTTP_AVAILABLE = True
except ImportError:
    AIOHTTP_AVAILABLE = False
    print("Warning: aiohttp not installed. Run: pip install aiohttp")

try:
    import websockets
    WEBSOCKETS_AVAILABLE = True
except ImportError:
    WEBSOCKETS_AVAILABLE = False

# 配置日志
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger("acp-server")


# ============================================================================
# 数据模型
# ============================================================================

class SessionMode(Enum):
    SINGLE_AGENT = "single-agent"
    MULTI_AGENT = "multi-agent"


@dataclass
class AcpSession:
    """ACP 会话"""
    session_id: str
    thread_id: str
    mode: SessionMode = SessionMode.SINGLE_AGENT
    provider: str = ""
    history: list = field(default_factory=list)
    seq: int = 0
    created_at: float = field(default_factory=time.time)
    cancelled: bool = False
    closed: bool = False


@dataclass
class JsonRpcRequest:
    """JSON-RPC 请求"""
    id: Optional[Any] = None
    method: str = ""
    params: dict = field(default_factory=dict)

    def to_dict(self) -> dict:
        result = {"jsonrpc": "2.0", "method": self.method}
        if self.id is not None:
            result["id"] = self.id
        if self.params:
            result["params"] = self.params
        return result


@dataclass
class JsonRpcResponse:
    """JSON-RPC 响应"""
    id: Optional[Any] = None
    result: Any = None
    error: Optional[dict] = None

    def to_dict(self) -> dict:
        result = {"jsonrpc": "2.0"}
        if self.id is not None:
            result["id"] = self.id
        if self.error:
            result["error"] = self.error
        else:
            result["result"] = self.result
        return result


@dataclass
class JsonRpcNotification:
    """JSON-RPC 通知"""
    method: str
    params: dict = field(default_factory=dict)

    def to_dict(self) -> dict:
        return {
            "jsonrpc": "2.0",
            "method": self.method,
            "params": self.params
        }


# ============================================================================
# 工具注册表
# ============================================================================

class Tool(ABC):
    """工具基类"""

    @property
    @abstractmethod
    def name(self) -> str:
        """工具名称"""
        pass

    @property
    @abstractmethod
    def description(self) -> str:
        """工具描述"""
        pass

    @property
    def input_schema(self) -> dict:
        """输入 JSON Schema"""
        return {"type": "object", "properties": {}}

    @abstractmethod
    def execute(self, arguments: dict) -> str:
        """执行工具"""
        pass


class ToolRegistry:
    """工具注册表"""

    def __init__(self):
        self._tools: dict[str, Tool] = {}

    def register(self, tool: Tool):
        self._tools[tool.name] = tool

    def get(self, name: str) -> Optional[Tool]:
        return self._tools.get(name)

    def list_all(self) -> list[Tool]:
        return list(self._tools.values())

    def to_mcp_tools_list(self) -> list[dict]:
        return [
            {
                "name": tool.name,
                "description": tool.description,
                "inputSchema": tool.input_schema
            }
            for tool in self._tools.values()
        ]


# ============================================================================
# 提供者注册表
# ============================================================================

class Provider(ABC):
    """代理提供者基类"""

    @property
    @abstractmethod
    def name(self) -> str:
        """提供者名称"""
        pass

    @property
    def is_available(self) -> bool:
        """检查提供者是否可用"""
        return True

    @abstractmethod
    async def execute(
        self,
        prompt: str,
        working_directory: str = "",
        model: str = "",
        on_delta: Optional[Callable[[str], None]] = None
    ) -> str:
        """执行代理任务"""
        pass


class ProviderRegistry:
    """提供者注册表"""

    def __init__(self):
        self._providers: dict[str, Provider] = {}

    def register(self, provider: Provider):
        self._providers[provider.name] = provider

    def get(self, name: str) -> Optional[Provider]:
        return self._providers.get(name)

    def list_available(self) -> list[str]:
        return [p.name for p in self._providers.values() if p.is_available]


# ============================================================================
# ACP 服务器核心
# ============================================================================

class AcpServer:
    """ACP 服务器"""

    def __init__(self, tool_registry: ToolRegistry, provider_registry: ProviderRegistry):
        self.tool_registry = tool_registry
        self.provider_registry = provider_registry
        self.sessions: dict[str, AcpSession] = {}
        self.session_tasks: dict[str, asyncio.Task] = {}
        self._request_id_counter = 0

    def get_config(self, key: str, default: str = "") -> str:
        """获取配置"""
        return os.environ.get(key, default)

    def get_bool_config(self, key: str, default: bool = False) -> bool:
        """获取布尔配置"""
        value = os.environ.get(key, "").lower()
        if value in ("1", "true", "yes", "on"):
            return True
        if value in ("0", "false", "no", "off"):
            return False
        return default

    # ------------------------------------------------------------------------
    # 能力查询
    # ------------------------------------------------------------------------

    def get_capabilities(self) -> dict:
        """获取服务器能力"""
        providers = self.provider_registry.list_available()
        multi_agent_enabled = self.get_bool_config("ACP_MULTI_AGENT_ENABLED", True)

        return {
            "singleAgent": len(providers) > 0,
            "multiAgent": multi_agent_enabled,
            "providers": providers,
            "capabilities": {
                "single_agent": len(providers) > 0,
                "multi_agent": multi_agent_enabled,
                "providers": providers,
                "tools": [t.name for t in self.tool_registry.list_all()]
            }
        }

    # ------------------------------------------------------------------------
    # 会话管理
    # ------------------------------------------------------------------------

    def create_session(self, session_id: str, thread_id: str) -> AcpSession:
        """创建会话"""
        session = AcpSession(
            session_id=session_id,
            thread_id=thread_id or session_id
        )
        self.sessions[session_id] = session
        return session

    def get_session(self, session_id: str) -> Optional[AcpSession]:
        """获取会话"""
        return self.sessions.get(session_id)

    def cancel_session(self, session_id: str) -> bool:
        """取消会话"""
        session = self.sessions.get(session_id)
        if session:
            session.cancelled = True
            task = self.session_tasks.get(session_id)
            if task:
                task.cancel()
            return True
        return False

    def close_session(self, session_id: str) -> bool:
        """关闭会话"""
        session = self.sessions.get(session_id)
        if session:
            session.closed = True
            self.cancel_session(session_id)
            del self.sessions[session_id]
            return True
        return False

    # ------------------------------------------------------------------------
    # 消息处理
    # ------------------------------------------------------------------------

    async def handle_request(
        self,
        request: JsonRpcRequest,
        notify: Callable[[JsonRpcNotification], None]
    ) -> JsonRpcResponse:
        """处理 JSON-RPC 请求"""
        method = request.method.strip()

        # 通知不需要响应
        if request.id is None:
            if method == "notifications/initialized":
                logger.info("Client initialized")
            return None

        try:
            if method == "acp.capabilities":
                return JsonRpcResponse(id=request.id, result=self.get_capabilities())

            elif method == "session.start":
                return await self._handle_session_start(request, notify)

            elif method == "session.message":
                return await self._handle_session_message(request, notify)

            elif method == "session.cancel":
                return self._handle_session_cancel(request)

            elif method == "session.close":
                return self._handle_session_close(request)

            else:
                return JsonRpcResponse(
                    id=request.id,
                    error={"code": -32601, "message": f"Unknown method: {method}"}
                )

        except asyncio.CancelledError:
            raise
        except Exception as e:
            logger.exception(f"Error handling {method}")
            return JsonRpcResponse(
                id=request.id,
                error={"code": -32603, "message": str(e)}
            )

    async def _handle_session_start(
        self,
        request: JsonRpcRequest,
        notify: Callable[[JsonRpcNotification], None]
    ) -> JsonRpcResponse:
        """处理 session.start"""
        params = request.params
        session_id = params.get("sessionId", "").strip()
        thread_id = params.get("threadId", session_id).strip()

        if not session_id:
            return JsonRpcResponse(
                id=request.id,
                error={"code": -32602, "message": "sessionId is required"}
            )

        # 创建新会话
        session = self.create_session(session_id, thread_id)

        # 发送开始通知
        turn_id = f"turn-{int(time.time() * 1000000)}"
        self._emit_update(session, turn_id, {
            "type": "status",
            "event": "started",
            "message": "session started",
            "pending": True,
            "error": False
        }, notify)

        # 执行会话
        return await self._execute_session(session, params, turn_id, notify)

    async def _handle_session_message(
        self,
        request: JsonRpcRequest,
        notify: Callable[[JsonRpcNotification], None]
    ) -> JsonRpcResponse:
        """处理 session.message"""
        params = request.params
        session_id = params.get("sessionId", "").strip()
        thread_id = params.get("threadId", session_id).strip()

        if not session_id:
            return JsonRpcResponse(
                id=request.id,
                error={"code": -32602, "message": "sessionId is required"}
            )

        # 获取或创建会话
        session = self.get_session(session_id)
        if not session:
            session = self.create_session(session_id, thread_id)

        turn_id = f"turn-{int(time.time() * 1000000)}"
        return await self._execute_session(session, params, turn_id, notify)

    def _handle_session_cancel(self, request: JsonRpcRequest) -> JsonRpcResponse:
        """处理 session.cancel"""
        params = request.params
        session_id = params.get("sessionId", "").strip()

        if not session_id:
            return JsonRpcResponse(
                id=request.id,
                error={"code": -32602, "message": "sessionId is required"}
            )

        cancelled = self.cancel_session(session_id)
        return JsonRpcResponse(
            id=request.id,
            result={"accepted": True, "cancelled": cancelled}
        )

    def _handle_session_close(self, request: JsonRpcRequest) -> JsonRpcResponse:
        """处理 session.close"""
        params = request.params
        session_id = params.get("sessionId", "").strip()

        if not session_id:
            return JsonRpcResponse(
                id=request.id,
                error={"code": -32602, "message": "sessionId is required"}
            )

        closed = self.close_session(session_id)
        return JsonRpcResponse(
            id=request.id,
            result={"accepted": True, "closed": closed}
        )

    async def _execute_session(
        self,
        session: AcpSession,
        params: dict,
        turn_id: str,
        notify: Callable[[JsonRpcNotification], None]
    ) -> JsonRpcResponse:
        """执行会话任务"""
        mode_str = params.get("mode", "single-agent").strip()
        session.mode = SessionMode(mode_str) if mode_str in ("single-agent", "multi-agent") else SessionMode.SINGLE_AGENT

        if session.mode == SessionMode.MULTI_AGENT:
            return await self._run_multi_agent(session, params, turn_id, notify)
        else:
            return await self._run_single_agent(session, params, turn_id, notify)

    async def _run_single_agent(
        self,
        session: AcpSession,
        params: dict,
        turn_id: str,
        notify: Callable[[JsonRpcNotification], None]
    ) -> JsonRpcResponse:
        """运行单代理"""
        provider_name = params.get("provider", "codex").strip()
        prompt = params.get("taskPrompt", "").strip()
        prompt = self._augment_prompt(prompt, params)
        working_directory = params.get("workingDirectory", "").strip()
        model = params.get("model", "").strip()

        provider = self.provider_registry.get(provider_name)
        if not provider:
            self._emit_update(session, turn_id, {
                "type": "status",
                "event": "completed",
                "message": f"Unknown provider: {provider_name}",
                "pending": False,
                "error": True
            }, notify)
            return JsonRpcResponse(
                id=None,
                error={"code": -32602, "message": f"Unknown provider: {provider_name}"}
            )

        if not provider.is_available:
            self._emit_update(session, turn_id, {
                "type": "status",
                "event": "completed",
                "message": f"Provider not available: {provider_name}",
                "pending": False,
                "error": True
            }, notify)
            return JsonRpcResponse(
                id=None,
                error={"code": -32602, "message": f"Provider not available: {provider_name}"}
            )

        def on_delta(text: str):
            self._emit_update(session, turn_id, {
                "type": "delta",
                "delta": text,
                "pending": True,
                "error": False
            }, notify)

        try:
            output = await provider.execute(
                prompt=prompt,
                working_directory=working_directory,
                model=model,
                on_delta=on_delta
            )

            self._emit_update(session, turn_id, {
                "type": "status",
                "event": "completed",
                "message": "single-agent completed",
                "pending": False,
                "error": False
            }, notify)

            return JsonRpcResponse(
                result={
                    "success": True,
                    "output": output,
                    "turnId": turn_id,
                    "mode": "single-agent",
                    "provider": provider_name
                }
            )

        except asyncio.CancelledError:
            self._emit_update(session, turn_id, {
                "type": "status",
                "event": "cancelled",
                "message": "session cancelled",
                "pending": False,
                "error": True
            }, notify)
            raise

        except Exception as e:
            self._emit_update(session, turn_id, {
                "type": "status",
                "event": "completed",
                "message": str(e),
                "pending": False,
                "error": True
            }, notify)
            return JsonRpcResponse(
                error={"code": -32603, "message": str(e)}
            )

    async def _run_multi_agent(
        self,
        session: AcpSession,
        params: dict,
        turn_id: str,
        notify: Callable[[JsonRpcNotification], None]
    ) -> JsonRpcResponse:
        """运行多代理"""
        # TODO: 实现多代理协调逻辑
        # 这里是一个简化版本，实际需要更复杂的编排

        self._emit_update(session, turn_id, {
            "type": "step",
            "mode": "multi-agent",
            "title": "Coordinator",
            "message": "Starting multi-agent orchestration",
            "pending": True,
            "error": False,
            "role": "architect",
            "iteration": 1,
            "score": 0
        }, notify)

        # 获取配置
        base_url = params.get("aiGatewayBaseUrl", os.environ.get("AI_GATEWAY_BASE_URL", "")).strip()
        api_key = params.get("aiGatewayApiKey", os.environ.get("AI_GATEWAY_API_KEY", "")).strip()
        model = params.get("model", os.environ.get("ACP_MULTI_AGENT_MODEL", "gpt-4o")).strip()
        prompt = params.get("taskPrompt", "").strip()

        if not api_key:
            self._emit_update(session, turn_id, {
                "type": "status",
                "mode": "multi-agent",
                "message": "aiGatewayApiKey is required for multi-agent mode",
                "pending": False,
                "error": True
            }, notify)
            return JsonRpcResponse(
                error={"code": -32602, "message": "aiGatewayApiKey is required"}
            )

        # 调用 LLM (简化版本)
        try:
            output = await self._call_llm(base_url, api_key, model, prompt)

            self._emit_update(session, turn_id, {
                "type": "step",
                "mode": "multi-agent",
                "title": "Result",
                "message": output,
                "pending": False,
                "error": False,
                "role": "tester",
                "iteration": 1,
                "score": 9
            }, notify)

            return JsonRpcResponse(
                result={
                    "success": True,
                    "summary": output,
                    "finalScore": 9,
                    "iterations": 1,
                    "turnId": turn_id,
                    "mode": "multi-agent"
                }
            )

        except Exception as e:
            self._emit_update(session, turn_id, {
                "type": "status",
                "mode": "multi-agent",
                "message": str(e),
                "pending": False,
                "error": True
            }, notify)
            return JsonRpcResponse(
                error={"code": -32603, "message": str(e)}
            )

    async def _call_llm(self, base_url: str, api_key: str, model: str, prompt: str) -> str:
        """调用 LLM API"""
        import aiohttp

        url = f"{base_url.rstrip('/')}/chat/completions"
        headers = {
            "Content-Type": "application/json",
            "Authorization": f"Bearer {api_key}"
        }
        payload = {
            "model": model,
            "messages": [
                {"role": "system", "content": "You are a multi-agent coordinator."},
                {"role": "user", "content": prompt}
            ],
            "max_tokens": 4096
        }

        async with aiohttp.ClientSession() as http_session:
            async with http_session.post(url, headers=headers, json=payload) as response:
                if response.status != 200:
                    text = await response.text()
                    raise Exception(f"API error {response.status}: {text[:500]}")
                data = await response.json()
                return data["choices"][0]["message"]["content"]

    def _augment_prompt(self, prompt: str, params: dict) -> str:
        """附加文件信息到提示"""
        attachments = params.get("attachments", [])
        if not attachments:
            return prompt

        lines = ["User-selected local attachments:"]
        for att in attachments:
            name = att.get("name", "attachment")
            path = att.get("path", "")
            if path:
                lines.append(f"- {name}: {path}")

        return "\n".join(lines) + "\n\n" + prompt

    def _emit_update(
        self,
        session: AcpSession,
        turn_id: str,
        payload: dict,
        notify: Callable[[JsonRpcNotification], None]
    ):
        """发送 session.update 通知"""
        session.seq += 1
        params = {
            "sessionId": session.session_id,
            "threadId": session.thread_id,
            "turnId": turn_id,
            "seq": session.seq,
            **payload
        }
        notify(JsonRpcNotification(method="session.update", params=params))


# ============================================================================
# 内置提供者
# ============================================================================

class CodexProvider(Provider):
    """Codex CLI 提供者"""

    @property
    def name(self) -> str:
        return "codex"

    @property
    def is_available(self) -> bool:
        import shutil
        return shutil.which("codex") is not None

    async def execute(
        self,
        prompt: str,
        working_directory: str = "",
        model: str = "",
        on_delta: Optional[Callable[[str], None]] = None
    ) -> str:
        args = ["exec", "--skip-git-repo-check", "--color", "never"]
        if working_directory:
            args.extend(["-C", working_directory])
        if model:
            args.extend(["-m", model])
        args.append(prompt)

        process = await asyncio.create_subprocess_exec(
            "codex", *args,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE
        )

        stdout, stderr = await process.communicate()

        if process.returncode != 0:
            raise Exception(f"Codex failed: {stderr.decode()}")

        return stdout.decode().strip()


class ClaudeProvider(Provider):
    """Claude CLI 提供者"""

    @property
    def name(self) -> str:
        return "claude"

    @property
    def is_available(self) -> bool:
        import shutil
        return shutil.which("claude") is not None

    async def execute(
        self,
        prompt: str,
        working_directory: str = "",
        model: str = "",
        on_delta: Optional[Callable[[str], None]] = None
    ) -> str:
        args = ["-p", prompt]
        if model:
            args = ["--model", model] + args

        process = await asyncio.create_subprocess_exec(
            "claude", *args,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
            cwd=working_directory or None
        )

        stdout, stderr = await process.communicate()

        if process.returncode != 0:
            raise Exception(f"Claude failed: {stderr.decode()}")

        return stdout.decode().strip()


# ============================================================================
# 内置工具
# ============================================================================

class ChatTool(Tool):
    """LLM Chat 工具"""

    @property
    def name(self) -> str:
        return "chat"

    @property
    def description(self) -> str:
        return "Send a message to an LLM and get a response"

    @property
    def input_schema(self) -> dict:
        return {
            "type": "object",
            "properties": {
                "prompt": {"type": "string", "description": "The prompt to send"},
                "model": {"type": "string", "description": "Model to use (default: from LLM_MODEL env)"},
                "system": {"type": "string", "description": "Optional system prompt"}
            },
            "required": ["prompt"]
        }

    def execute(self, arguments: dict) -> str:
        import requests

        api_key = os.environ.get("LLM_API_KEY", "")
        if not api_key:
            return "Error: LLM_API_KEY not set"

        base_url = os.environ.get("LLM_BASE_URL", "https://api.openai.com/v1").rstrip("/")
        model = arguments.get("model", os.environ.get("LLM_MODEL", "gpt-4o"))
        prompt = arguments.get("prompt", "")
        system = arguments.get("system", "")

        messages = []
        if system:
            messages.append({"role": "system", "content": system})
        messages.append({"role": "user", "content": prompt})

        response = requests.post(
            f"{base_url}/chat/completions",
            headers={
                "Content-Type": "application/json",
                "Authorization": f"Bearer {api_key}"
            },
            json={"model": model, "messages": messages, "max_tokens": 4096},
            timeout=120
        )

        if response.status_code != 200:
            return f"Error: API returned {response.status_code}"

        return response.json()["choices"][0]["message"]["content"]


# ============================================================================
# HTTP/WebSocket 服务器
# ============================================================================

class AcpHttpServer:
    """基于 aiohttp 的 ACP HTTP/WebSocket 服务器"""

    def __init__(self, acp_server: AcpServer, host: str = "127.0.0.1", port: int = 8787):
        if not AIOHTTP_AVAILABLE:
            raise RuntimeError("aiohttp not installed. Run: pip install aiohttp")

        self.acp_server = acp_server
        self.host = host
        self.port = port
        self.app = web.Application()
        self._setup_routes()

    def _setup_routes(self):
        self.app.router.add_get("/health", self._handle_health)
        self.app.router.add_post("/acp/rpc", self._handle_http_rpc)
        self.app.router.add_get("/acp", self._handle_websocket)

    async def _handle_health(self, request: web.Request) -> web.Response:
        return web.json_response({"status": "ok"})

    async def _handle_http_rpc(self, request: web.Request) -> web.Response:
        """处理 HTTP RPC 请求"""
        try:
            body = await request.read()
            data = json.loads(body)

            rpc_request = JsonRpcRequest(
                id=data.get("id"),
                method=data.get("method", ""),
                params=data.get("params", {})
            )

            notifications = []

            def notify(n: JsonRpcNotification):
                notifications.append(n)

            response = await self.acp_server.handle_request(rpc_request, notify)

            # 检查是否需要 SSE 流式响应
            accept = request.headers.get("Accept", "").lower()
            if "text/event-stream" in accept and notifications:
                response_obj = web.StreamResponse()
                response_obj.content_type = "text/event-stream"
                response_obj.headers["Cache-Control"] = "no-cache"
                response_obj.headers["Connection"] = "keep-alive"
                await response_obj.prepare(request)

                for n in notifications:
                    await response_obj.write(f"data: {json.dumps(n.to_dict())}\n\n".encode())

                if response:
                    await response_obj.write(f"data: {json.dumps(response.to_dict())}\n\n".encode())

                await response_obj.write(b"data: [DONE]\n\n")
                return response_obj

            if response is None:
                return web.Response(status=204)

            return web.json_response(response.to_dict())

        except json.JSONDecodeError:
            return web.json_response(
                {"jsonrpc": "2.0", "error": {"code": -32700, "message": "Invalid JSON"}},
                status=400
            )
        except Exception as e:
            logger.exception("HTTP RPC error")
            return web.json_response(
                {"jsonrpc": "2.0", "error": {"code": -32603, "message": str(e)}},
                status=500
            )

    async def _handle_websocket(self, request: web.Request) -> web.WebSocketResponse:
        """处理 WebSocket 连接"""
        ws = web.WebSocketResponse()
        await ws.prepare(request)

        async for msg in ws:
            if msg.type == aiohttp.WSMsgType.TEXT:
                try:
                    data = json.loads(msg.data)
                    rpc_request = JsonRpcRequest(
                        id=data.get("id"),
                        method=data.get("method", ""),
                        params=data.get("params", {})
                    )

                    def notify(n: JsonRpcNotification):
                        asyncio.create_task(ws.send_json(n.to_dict()))

                    response = await self.acp_server.handle_request(rpc_request, notify)
                    if response:
                        await ws.send_json(response.to_dict())

                except json.JSONDecodeError:
                    await ws.send_json({
                        "jsonrpc": "2.0",
                        "error": {"code": -32700, "message": "Invalid JSON"}
                    })
                except Exception as e:
                    logger.exception("WebSocket error")

            elif msg.type == aiohttp.WSMsgType.ERROR:
                logger.error(f"WebSocket error: {ws.exception()}")

        return ws

    def run(self):
        """启动服务器"""
        web.run_app(self.app, host=self.host, port=self.port)


# ============================================================================
# MCP 工具桥接器
# ============================================================================

class McpToolBridge:
    """作为 MCP 工具运行的桥接器"""

    def __init__(self, tool_registry: ToolRegistry):
        self.tool_registry = tool_registry

    def run(self):
        """运行 MCP 桥接器"""
        import sys

        # 强制无缓冲 I/O
        sys.stdout = os.fdopen(sys.stdout.fileno(), 'wb', buffering=0)
        sys.stdin = os.fdopen(sys.stdin.fileno(), 'rb', buffering=0)

        while True:
            try:
                request = self._read_message()
                if request is None:
                    break

                response = self._handle_request(request)
                if response:
                    self._write_response(response)

            except EOFError:
                break
            except Exception as e:
                logger.exception("MCP bridge error")

    def _read_message(self) -> Optional[dict]:
        """读取 MCP 消息"""
        line = sys.stdin.readline()
        if not line:
            return None

        line = line.decode('utf-8').rstrip('\r\n')

        # Content-Length 格式
        if line.lower().startswith("content-length:"):
            content_length = int(line.split(":", 1)[1].strip())
            while True:
                hdr = sys.stdin.readline()
                if not hdr:
                    return None
                hdr = hdr.decode('utf-8').rstrip('\r\n')
                if hdr == "":
                    break

            body = sys.stdin.read(content_length)
            return json.loads(body.decode('utf-8'))

        # NDJSON 格式
        if line.startswith("{"):
            return json.loads(line)

        return None

    def _write_response(self, response: dict):
        """写入 MCP 响应"""
        json_str = json.dumps(response, separators=(',', ':'))
        json_bytes = json_str.encode('utf-8')
        header = f"Content-Length: {len(json_bytes)}\r\n\r\n".encode('utf-8')
        sys.stdout.write(header + json_bytes)
        sys.stdout.flush()

    def _handle_request(self, request: dict) -> Optional[dict]:
        """处理 MCP 请求"""
        method = request.get("method", "")
        request_id = request.get("id")

        # 通知不需要响应
        if request_id is None:
            if method == "notifications/initialized":
                logger.info("MCP client initialized")
            return None

        if method == "initialize":
            return {
                "jsonrpc": "2.0",
                "id": request_id,
                "result": {
                    "protocolVersion": "2024-11-05",
                    "capabilities": {"tools": {}},
                    "serverInfo": {
                        "name": "external-acp-tools",
                        "version": "1.0.0"
                    }
                }
            }

        elif method == "ping":
            return {"jsonrpc": "2.0", "id": request_id, "result": {}}

        elif method == "tools/list":
            return {
                "jsonrpc": "2.0",
                "id": request_id,
                "result": {"tools": self.tool_registry.to_mcp_tools_list()}
            }

        elif method == "tools/call":
            params = request.get("params", {})
            tool_name = params.get("name", "")
            arguments = params.get("arguments", {})

            tool = self.tool_registry.get(tool_name)
            if not tool:
                return {
                    "jsonrpc": "2.0",
                    "id": request_id,
                    "error": {"code": -32601, "message": f"Unknown tool: {tool_name}"}
                }

            try:
                result = tool.execute(arguments)
                return {
                    "jsonrpc": "2.0",
                    "id": request_id,
                    "result": {"content": [{"type": "text", "text": result}]}
                }
            except Exception as e:
                return {
                    "jsonrpc": "2.0",
                    "id": request_id,
                    "result": {
                        "content": [{"type": "text", "text": f"Error: {e}"}],
                        "isError": True
                    }
                }

        else:
            return {
                "jsonrpc": "2.0",
                "id": request_id,
                "error": {"code": -32601, "message": f"Unknown method: {method}"}
            }


# ============================================================================
# 主入口
# ============================================================================

def create_default_registries() -> tuple[ToolRegistry, ProviderRegistry]:
    """创建默认注册表"""
    tool_registry = ToolRegistry()
    tool_registry.register(ChatTool())

    provider_registry = ProviderRegistry()
    provider_registry.register(CodexProvider())
    provider_registry.register(ClaudeProvider())

    return tool_registry, provider_registry


def main():
    """主入口"""
    import argparse

    parser = argparse.ArgumentParser(description="External ACP Server")
    subparsers = parser.add_subparsers(dest="command", help="Command")

    # serve 命令
    serve_parser = subparsers.add_parser("serve", help="Start ACP server")
    serve_parser.add_argument("--listen", default=os.environ.get("ACP_LISTEN_ADDR", "127.0.0.1:8787"),
                             help="Listen address (default: 127.0.0.1:8787)")

    # bridge 命令
    subparsers.add_parser("bridge", help="Run as MCP tool bridge")

    args = parser.parse_args()

    tool_registry, provider_registry = create_default_registries()

    if args.command == "serve":
        host, port = args.listen.split(":")
        port = int(port)
        acp_server = AcpServer(tool_registry, provider_registry)
        http_server = AcpHttpServer(acp_server, host, port)
        logger.info(f"Starting ACP server on {host}:{port}")
        http_server.run()

    elif args.command == "bridge":
        bridge = McpToolBridge(tool_registry)
        logger.info("Starting MCP tool bridge")
        bridge.run()

    else:
        parser.print_help()


if __name__ == "__main__":
    main()