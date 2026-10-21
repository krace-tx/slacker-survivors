"""Blender MCP Server 入口。

从 stdio 接收 MCP 协议消息，通过 BlenderBridge 转发到
Blender Addon 的 TCP Socket 服务器，实现 AI 对 Blender 的远程控制。

Usage::

    blender-mcp [--host HOST] [--port PORT]
"""
from __future__ import annotations

import argparse
import os
import sys

# 确保包根目录在 import 路径中
_parent = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if _parent not in sys.path:
    sys.path.insert(0, _parent)

from mcp.server.mcpserver import MCPServer

from blender_mcp.shared.constants import DEFAULT_HOST, DEFAULT_PORT
from .bridge import BlenderBridge
from .tools import register_all_tools


def create_server(
    host: str = DEFAULT_HOST,
    port: int = DEFAULT_PORT,
) -> MCPServer:
    """创建并配置 MCP 服务器。

    Args:
        host: Blender Addon 的 TCP 监听地址。
        port: Blender Addon 的 TCP 监听端口。

    Returns:
        已注册所有 Tool 的 MCPServer 实例。
    """
    mcp = MCPServer("Blender MCP")
    bridge = BlenderBridge(host=host, port=port)

    # blender_ping 作为系统级 Tool，直接定义在入口
    @mcp.tool()
    async def blender_ping() -> str:
        """Check if Blender is running and the MCP addon is connected."""
        try:
            result = await bridge.send_command("system.ping")
            version = result.get("blender_version", "unknown")
            return f"✅ Blender is connected! Version: {version}"
        except Exception as exc:
            return (
                f"❌ Cannot reach Blender: {exc}. "
                "Make sure Blender is open and the MCP addon server is started."
            )

    # 注册所有领域 Tools
    register_all_tools(mcp, bridge)

    return mcp


def main() -> None:
    """CLI 入口：解析参数并启动 MCP 服务器。"""
    parser = argparse.ArgumentParser(description="Blender MCP Server")
    parser.add_argument(
        "--host",
        default=DEFAULT_HOST,
        help=f"Blender addon host (default: {DEFAULT_HOST})",
    )
    parser.add_argument(
        "--port",
        type=int,
        default=DEFAULT_PORT,
        help=f"Blender addon port (default: {DEFAULT_PORT})",
    )
    args = parser.parse_args()
    server = create_server(host=args.host, port=args.port)
    server.run(transport="stdio")


if __name__ == "__main__":
    main()
