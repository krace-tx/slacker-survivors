"""材质相关的 MCP Tool 定义。

提供 PBR 材质的创建、分配、颜色设置和列表查询操作。
"""
from __future__ import annotations

from mcp.server.mcpserver import MCPServer

from ..bridge import BlenderBridge
from ._fmt import fmt


def register_material_tools(mcp: MCPServer, bridge: BlenderBridge) -> None:
    """注册所有材质相关的 MCP Tools。

    Args:
        mcp: MCP 服务器实例。
        bridge: 与 Blender Addon 通信的 TCP 桥接客户端。
    """

    @mcp.tool()
    async def blender_create_material(
        name: str,
        color: list[float] = [0.8, 0.8, 0.8, 1.0],  # noqa: B006
        metallic: float = 0.0,
        roughness: float = 0.5,
    ) -> str:
        """Create a new PBR material.

        Args:
            name: Material name.
            color: [r, g, b, a] base color (0.0-1.0).
            metallic: Metallic value (0.0-1.0).
            roughness: Roughness value (0.0-1.0).
        """
        result = await bridge.send_command(
            "material.create",
            {
                "name": name,
                "color": color,
                "metallic": metallic,
                "roughness": roughness,
            },
        )
        return fmt("Create Material", result)

    @mcp.tool()
    async def blender_assign_material(object_name: str, material_name: str) -> str:
        """Assign an existing material to an object.

        Args:
            object_name: Name of the target object.
            material_name: Name of the material to assign.
        """
        result = await bridge.send_command(
            "material.assign",
            {"object_name": object_name, "material_name": material_name},
        )
        return fmt("Assign Material", result)

    @mcp.tool()
    async def blender_set_color(object_name: str, color: list[float]) -> str:
        """Set the base color of an object (creates material if needed).

        Args:
            object_name: Name of the target object.
            color: [r, g, b] or [r, g, b, a] color (0.0-1.0).
        """
        result = await bridge.send_command(
            "material.set_color",
            {"object_name": object_name, "color": color},
        )
        return fmt("Set Color", result)

    @mcp.tool()
    async def blender_list_materials() -> str:
        """List all materials in the current Blender file."""
        result = await bridge.send_command("material.list")
        return fmt("Materials", result)
