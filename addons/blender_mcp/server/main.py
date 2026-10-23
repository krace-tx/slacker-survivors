"""Blender MCP Server 入口。

对齐 Godot MCP ``server/src/index.ts``：创建 MCP 服务 → 装配全部 Tool 分组与
Resource 分组 → 配置 Blender 连接单例 → 以 stdio 传输启动。

Usage::

    blender-mcp [--host HOST] [--port PORT] [--timeout SECONDS]
    python -m blender_mcp.server [...]
"""
from __future__ import annotations

import argparse

from mcp.server.mcpserver import MCPServer

from ..shared.constants import BRIDGE_TIMEOUT, DEFAULT_HOST, DEFAULT_PORT
from .resources import ALL_RESOURCE_GROUPS
from .tools import ALL_TOOL_GROUPS
from .utils import configure_connection, log

_INSTRUCTIONS = (
    "Controls a live Blender session through the Blender MCP addon. "
    "Call blender_ping first to verify the connection. Object names are case-sensitive; "
    "rotations are in radians; colors are 0~1 floats. Every write operation is a single "
    "undo step, so blender_undo can revert mistakes. Use blender_viewport_snapshot or "
    "blender_render_snapshot to visually verify results."
)


def create_server(host: str = DEFAULT_HOST, port: int = DEFAULT_PORT,
                  timeout: float = BRIDGE_TIMEOUT) -> MCPServer:
    """创建并配置 MCP 服务器。"""
    configure_connection(host, port, timeout)

    mcp = MCPServer("Blender MCP", instructions=_INSTRUCTIONS)
    tool_count = 0
    for group in ALL_TOOL_GROUPS:
        group.install(mcp)
        tool_count += len(group.names)

    resource_count = 0
    for rgroup in ALL_RESOURCE_GROUPS:
        rgroup.install(mcp)
        resource_count += len(rgroup.uris)

    log(
        f"Registered {tool_count} tools ({len(ALL_TOOL_GROUPS)} groups) and "
        f"{resource_count} resources ({len(ALL_RESOURCE_GROUPS)} groups); "
        f"target Blender at {host}:{port}"
    )
    return mcp


def main() -> None:
    """CLI 入口：解析参数并以 stdio 传输启动 MCP 服务器。"""
    parser = argparse.ArgumentParser(description="Blender MCP Server")
    parser.add_argument("--host", default=DEFAULT_HOST, help=f"Blender addon host (default: {DEFAULT_HOST})")
    parser.add_argument("--port", type=int, default=DEFAULT_PORT, help=f"Blender addon port (default: {DEFAULT_PORT})")
    parser.add_argument("--timeout", type=float, default=BRIDGE_TIMEOUT,
                        help=f"Default command timeout in seconds (default: {BRIDGE_TIMEOUT:.0f})")
    args = parser.parse_args()

    # 不在启动时预连接：MCP 客户端往往先于 Blender 启动，连接在首次调用 Tool 时惰性建立
    create_server(args.host, args.port, args.timeout).run(transport="stdio")


if __name__ == "__main__":
    main()
