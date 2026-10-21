"""场景管理相关的 MCP Tool 定义。

每个 Tool 函数是 AI 可调用的外部接口，通过 BlenderBridge
将命令转发到 Blender Addon 端的对应 handler 执行。
"""
from __future__ import annotations

from mcp.server.mcpserver import MCPServer

from ..bridge import BlenderBridge
from ._fmt import fmt


def register_scene_tools(mcp: MCPServer, bridge: BlenderBridge) -> None:
    """注册所有场景相关的 MCP Tools。

    包含：列出对象、场景信息、清空场景、选择操作、撤销。

    Args:
        mcp: MCP 服务器实例。
        bridge: 与 Blender Addon 通信的 TCP 桥接客户端。
    """

    @mcp.tool()
    async def blender_list_objects(type_filter: str = "") -> str:
        """List all objects in the current Blender scene.

        Args:
            type_filter: Optional filter by type: MESH, ARMATURE, CAMERA,
                LIGHT, EMPTY.  Leave empty for all.
        """
        params: dict = {}
        if type_filter:
            params["type_filter"] = type_filter
        result = await bridge.send_command("scene.list_objects", params)
        return fmt("Scene Objects", result)

    @mcp.tool()
    async def blender_scene_info() -> str:
        """Get information about the current Blender scene (name, frame range, FPS, render engine, etc.)."""
        result = await bridge.send_command("scene.get_info")
        return fmt("Scene Info", result)

    @mcp.tool()
    async def blender_clear_scene(type_filter: str = "MESH") -> str:
        """⚠️ Destructive: Clear objects from the Blender scene.

        Args:
            type_filter: Type of objects to remove: MESH, ARMATURE, CAMERA,
                LIGHT, EMPTY, or ALL.
        """
        result = await bridge.send_command(
            "scene.clear", {"type_filter": type_filter, "confirm": True}
        )
        return fmt("Clear Scene", result)

    @mcp.tool()
    async def blender_select(
        object_names: list[str] = [],  # noqa: B006
        select_all: bool = False,
        deselect_all: bool = False,
    ) -> str:
        """Select or deselect objects in the Blender scene.

        Args:
            object_names: List of object names to select.
            select_all: If true, select all objects.
            deselect_all: If true, deselect all objects.
        """
        params: dict = {}
        if deselect_all:
            params["deselect"] = True
            params["all"] = True
        elif select_all:
            params["all"] = True
        else:
            params["object_names"] = object_names
        result = await bridge.send_command("scene.select", params)
        return fmt("Selection", result)

    @mcp.tool()
    async def blender_undo() -> str:
        """Undo the last operation in Blender."""
        result = await bridge.send_command("scene.undo")
        return fmt("Undo", result)
