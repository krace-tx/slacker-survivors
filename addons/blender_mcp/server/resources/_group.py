"""Resource 分组注册器 (Resource Group)。

对齐 Godot MCP ``server/src/resources/*.ts``：每个领域文件声明一个
``ResourceGroup``，用装饰器收集只读 MCP Resource，由入口统一安装到 ``MCPServer``。
"""
from __future__ import annotations

from typing import Any, Callable

from mcp.server.mcpserver import MCPServer

ResourceFn = Callable[..., Any]


class ResourceGroup:
    """一组同领域的 MCP Resource。"""

    def __init__(self, name: str) -> None:
        self.name = name
        self._resources: list[tuple[str, dict[str, Any], ResourceFn]] = []

    def resource(
        self,
        uri: str,
        *,
        name: str | None = None,
        description: str | None = None,
        mime_type: str = "application/json",
    ) -> Callable[[ResourceFn], ResourceFn]:
        """声明一个 MCP Resource。"""

        def decorator(fn: ResourceFn) -> ResourceFn:
            meta = {
                "name": name or fn.__name__,
                "description": description or (fn.__doc__ or "").strip(),
                "mime_type": mime_type,
            }
            self._resources.append((uri, meta, fn))
            return fn

        return decorator

    @property
    def uris(self) -> list[str]:
        return [uri for uri, _, _ in self._resources]

    def install(self, mcp: MCPServer) -> None:
        for uri, meta, fn in self._resources:
            mcp.resource(uri, **meta)(fn)
