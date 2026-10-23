"""Tool 与 Resource 层公共调用与输出格式化。"""
from __future__ import annotations

import json
from typing import Any

from mcp.server.mcpserver.exceptions import ResourceError, ToolError

from .blender_connection import get_blender_connection


def fmt(title: str, result: Any) -> str:
    """将 Blender 返回结果格式化为 AI 可读的 Markdown（标题 + JSON 代码块）。"""
    body = json.dumps(result, indent=2, ensure_ascii=False)
    return f"**{title}**\n```json\n{body}\n```"


async def call(title: str, method: str, *, timeout: float | None = None, **params: Any) -> str:
    """调用 Blender 指令并格式化为 Tool Markdown 输出。

    值为 ``None`` 的参数会被剔除，交由 Addon 侧 CommandSpec 回填默认值，
    保证默认值只有一个事实来源。
    """
    clean = {k: v for k, v in params.items() if v is not None}
    try:
        result = await get_blender_connection().send_command(method, clean, timeout=timeout)
    except (ConnectionError, TimeoutError) as exc:
        raise ToolError(str(exc)) from exc
    return fmt(title, result)


async def fetch_json(method: str, **params: Any) -> str:
    """调用 Blender 指令并序列化为 JSON 字符串（供 MCP Resource 使用）。"""
    clean = {k: v for k, v in params.items() if v is not None}
    try:
        result = await get_blender_connection().send_command(method, clean)
    except (ConnectionError, TimeoutError, ToolError) as exc:
        raise ResourceError(str(exc)) from exc
    return json.dumps(result, indent=2, ensure_ascii=False)
