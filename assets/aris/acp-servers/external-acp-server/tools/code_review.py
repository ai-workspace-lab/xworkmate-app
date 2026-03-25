"""
示例自定义工具：代码审查工具

这个工具展示了如何扩展 ACP 服务器添加自定义工具。
"""


class CodeReviewTool:
    """代码审查工具 - 使用 LLM 审查代码变更"""

    @property
    def name(self) -> str:
        return "code_review"

    @property
    def description(self) -> str:
        return "Review code changes and provide feedback"

    @property
    def input_schema(self) -> dict:
        return {
            "type": "object",
            "properties": {
                "diff": {
                    "type": "string",
                    "description": "The git diff or code changes to review"
                },
                "context": {
                    "type": "string",
                    "description": "Optional context about the changes"
                },
                "focus": {
                    "type": "string",
                    "description": "Areas to focus on (security, performance, style, etc.)"
                }
            },
            "required": ["diff"]
        }

    def execute(self, arguments: dict) -> str:
        """
        执行代码审查

        实际实现中，你可以：
        1. 调用外部 LLM API
        2. 使用本地模型
        3. 执行静态分析工具
        4. 查询代码库知识库
        """
        import os

        diff = arguments.get("diff", "")
        context = arguments.get("context", "")
        focus = arguments.get("focus", "general")

        # 获取 LLM 配置
        api_key = os.environ.get("LLM_API_KEY", "")
        base_url = os.environ.get("LLM_BASE_URL", "https://api.openai.com/v1")
        model = os.environ.get("LLM_MODEL", "gpt-4o")

        if not api_key:
            return "Error: LLM_API_KEY environment variable not set"

        # 构建审查提示
        system_prompt = """You are an expert code reviewer. Analyze the provided code changes and provide:
1. Summary of changes
2. Potential issues (bugs, security, performance)
3. Code style suggestions
4. Overall assessment

Be concise and actionable."""

        if focus != "general":
            system_prompt += f"\n\nFocus particularly on: {focus}"

        user_prompt = f"Context: {context}\n\nCode changes:\n```\n{diff}\n```" if context else f"Code changes:\n```\n{diff}\n```"

        # 调用 LLM API
        try:
            import requests

            response = requests.post(
                f"{base_url.rstrip('/')}/chat/completions",
                headers={
                    "Content-Type": "application/json",
                    "Authorization": f"Bearer {api_key}"
                },
                json={
                    "model": model,
                    "messages": [
                        {"role": "system", "content": system_prompt},
                        {"role": "user", "content": user_prompt}
                    ],
                    "max_tokens": 4096
                },
                timeout=120
            )

            if response.status_code != 200:
                return f"Error: API returned {response.status_code}: {response.text[:200]}"

            return response.json()["choices"][0]["message"]["content"]

        except Exception as e:
            return f"Error: {e}"


# 注册工具的示例
def register_tools(registry):
    """注册所有自定义工具"""
    from .base import Tool

    # 注册代码审查工具
    registry.register(CodeReviewTool())

    # 在这里添加更多工具...
    # registry.register(AnotherTool())