"""Tool 分组注册器 (Tool Group)。

对齐 Godot MCP ``server/src/tools/*.ts`` 中 ``export const xxxTools: MCPTool[]``
的声明式风格：每个领域文件声明一个 ``ToolGroup``，用装饰器收集 Tool 及其
行为注解（只读 / 破坏性 / 幂等），由入口统一 ``install`` 到 MCPServer。
"""
from __future__ import annotations

from typing import Any, Callable

from mcp.server.mcpserver import MCPServer
from mcp.types import ToolAnnotations

ToolFn = Callable[..., Any]


class ToolGroup:
    """一组同领域的 MCP Tool。"""

    def __init__(self, name: str) -> None:
        self.name = name
        self._tools: list[tuple[ToolFn, ToolAnnotations]] = []

    def tool(self, *, read_only: bool = False, destructive: bool = False,
             idempotent: bool = False) -> Callable[[ToolFn], ToolFn]:
        """声明一个 Tool。

        Args:
            read_only: 不修改 Blender 状态（查询类）。
            destructive: 可能删除数据（客户端可据此要求用户确认）。
            idempotent: 相同参数重复调用结果一致。
        """

        def decorator(fn: ToolFn) -> ToolFn:
            annotations = ToolAnnotations(
                read_only_hint=read_only,
                destructive_hint=destructive,
                idempotent_hint=idempotent or read_only,
                open_world_hint=False,
            )
            self._tools.append((fn, annotations))
            return fn

        return decorator

    @property
    def names(self) -> list[str]:
        return [fn.__name__ for fn, _ in self._tools]

    def install(self, mcp: MCPServer) -> None:
        for fn, annotations in self._tools:
            mcp.add_tool(fn, annotations=annotations)
