"""
Tool base classes for external ACP server
"""

from abc import ABC, abstractmethod
from typing import Any, Optional


class Tool(ABC):
    """
    工具基类

    所有自定义工具必须继承此类并实现以下方法：
    - name: 工具名称
    - description: 工具描述
    - input_schema: 输入参数 JSON Schema
    - execute: 执行逻辑
    """

    @property
    @abstractmethod
    def name(self) -> str:
        """
        工具名称

        必须唯一，使用小写字母和下划线，例如: code_review
        """
        pass

    @property
    @abstractmethod
    def description(self) -> str:
        """
        工具描述

        简短描述工具的功能，用于 AI 选择合适的工具
        """
        pass

    @property
    def input_schema(self) -> dict:
        """
        输入参数 JSON Schema

        定义工具接受的参数结构
        """
        return {
            "type": "object",
            "properties": {},
            "required": []
        }

    @abstractmethod
    def execute(self, arguments: dict) -> str:
        """
        执行工具

        Args:
            arguments: 工具参数，根据 input_schema 验证

        Returns:
            工具执行结果，作为文本返回
        """
        pass


class ToolRegistry:
    """工具注册表"""

    def __init__(self):
        self._tools: dict[str, Tool] = {}

    def register(self, tool: Tool):
        """注册工具"""
        self._tools[tool.name] = tool

    def get(self, name: str) -> Optional[Tool]:
        """获取工具"""
        return self._tools.get(name)

    def list_all(self) -> list[Tool]:
        """列出所有工具"""
        return list(self._tools.values())

    def to_mcp_tools_list(self) -> list[dict]:
        """转换为 MCP 工具列表格式"""
        return [
            {
                "name": tool.name,
                "description": tool.description,
                "inputSchema": tool.input_schema
            }
            for tool in self._tools.values()
        ]