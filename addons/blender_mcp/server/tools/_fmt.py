"""MCP Tool 输出格式化工具。

将 Blender 返回的结果字典格式化为 AI 可读的 Markdown 文本块，
统一所有 Tool 的输出风格。
"""
from __future__ import annotations

import json


def fmt(title: str, result: dict) -> str:
    """将 Blender 返回的结果字典格式化为 AI 可读的 Markdown。

    Args:
        title: 显示在 Markdown 粗体标题中的文字。
        result: Blender 返回的 JSON 结果字典。

    Returns:
        包含标题和 JSON 代码块的 Markdown 字符串。
    """
    return f"**{title}**\n```json\n{json.dumps(result, indent=2, ensure_ascii=False)}\n```"
