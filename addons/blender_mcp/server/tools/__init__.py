"""MCP Tool 注册包。

提供 register_all_tools() 函数，集中注册所有领域的 Tool。
"""
from __future__ import annotations

from mcp.server.mcpserver import MCPServer

from ..bridge import BlenderBridge
from .environment_tools import register_environment_tools
from .material_tools import register_material_tools
from .modeling_tools import register_modeling_tools
from .modifier_tools import register_modifier_tools
from .scene_tools import register_scene_tools


def register_all_tools(mcp: MCPServer, bridge: BlenderBridge) -> None:
    """注册所有 MCP Tools 到服务器实例。

    按领域分组依次注册：场景 → 建模 → 修改器 → 材质 → 环境。

    Args:
        mcp: MCP 服务器实例。
        bridge: 与 Blender Addon 通信的 TCP 桥接客户端。
    """
    register_scene_tools(mcp, bridge)
    register_modeling_tools(mcp, bridge)
    register_modifier_tools(mcp, bridge)
    register_material_tools(mcp, bridge)
    register_environment_tools(mcp, bridge)
