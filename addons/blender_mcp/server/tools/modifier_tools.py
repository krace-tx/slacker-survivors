"""修改器相关的 MCP Tool 定义。

提供 Blender 修改器的添加、应用、移除和列表查询操作。
"""
from __future__ import annotations

from mcp.server.mcpserver import MCPServer

from ..bridge import BlenderBridge
from ._fmt import fmt


def register_modifier_tools(mcp: MCPServer, bridge: BlenderBridge) -> None:
    """注册所有修改器相关的 MCP Tools。

    Args:
        mcp: MCP 服务器实例。
        bridge: 与 Blender Addon 通信的 TCP 桥接客户端。
    """

    @mcp.tool()
    async def blender_add_modifier(
        object_name: str,
        type: str = "SUBSURF",
        name: str = "",
        **kwargs: object,
    ) -> str:
        """Add a modifier to an object.

        Args:
            object_name: Name of the target object.
            type: Modifier type: SUBSURF, MIRROR, BOOLEAN, SOLIDIFY, ARRAY, BEVEL, DECIMATE, SMOOTH.
            name: Optional custom name for the modifier.
        """
        params: dict = {"object_name": object_name, "type": type}
        if name:
            params["name"] = name
        params.update(kwargs)
        result = await bridge.send_command("modifier.add", params)
        return fmt("Add Modifier", result)

    @mcp.tool()
    async def blender_apply_modifier(object_name: str, modifier_name: str) -> str:
        """Apply (bake) a modifier permanently onto the mesh.

        Args:
            object_name: Name of the target object.
            modifier_name: Name of the modifier to apply.
        """
        result = await bridge.send_command(
            "modifier.apply",
            {"object_name": object_name, "modifier_name": modifier_name},
        )
        return fmt("Apply Modifier", result)

    @mcp.tool()
    async def blender_remove_modifier(object_name: str, modifier_name: str) -> str:
        """Remove a modifier from an object.

        Args:
            object_name: Name of the target object.
            modifier_name: Name of the modifier to remove.
        """
        result = await bridge.send_command(
            "modifier.remove",
            {"object_name": object_name, "modifier_name": modifier_name},
        )
        return fmt("Remove Modifier", result)

    @mcp.tool()
    async def blender_list_modifiers(object_name: str) -> str:
        """List all modifiers on an object.

        Args:
            object_name: Name of the target object.
        """
        result = await bridge.send_command(
            "modifier.list", {"object_name": object_name}
        )
        return fmt("Modifiers", result)
