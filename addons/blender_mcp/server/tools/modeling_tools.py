"""网格建模相关的 MCP Tool 定义。

提供基础几何体创建、删除、重命名、变换、复制、合并、
平滑着色等建模操作的 AI 可调用接口。
"""
from __future__ import annotations

from mcp.server.mcpserver import MCPServer

from ..bridge import BlenderBridge
from ._fmt import fmt


def register_modeling_tools(mcp: MCPServer, bridge: BlenderBridge) -> None:
    """注册所有网格建模相关的 MCP Tools。

    Args:
        mcp: MCP 服务器实例。
        bridge: 与 Blender Addon 通信的 TCP 桥接客户端。
    """

    @mcp.tool()
    async def blender_add_primitive(
        type: str = "cube",
        name: str = "",
        location: list[float] = [0.0, 0.0, 0.0],  # noqa: B006
        rotation: list[float] = [0.0, 0.0, 0.0],  # noqa: B006
        scale: list[float] = [1.0, 1.0, 1.0],  # noqa: B006
        size: float = 1.0,
        segments: int = 32,
        rings: int = 16,
    ) -> str:
        """Add a primitive mesh object to the Blender scene.

        Args:
            type: Primitive type: cube, sphere, ico_sphere, cylinder, cone,
                torus, plane, circle, monkey, grid.
            name: Custom name for the object.  Leave empty for default.
            location: [x, y, z] world position.
            rotation: [rx, ry, rz] rotation in radians.
            scale: [sx, sy, sz] scale.
            size: Size / radius of the primitive.
            segments: Number of segments (for curved surfaces).
            rings: Number of rings (for sphere, torus).
        """
        params: dict = {
            "type": type,
            "size": size,
            "segments": segments,
            "rings": rings,
        }
        if name:
            params["name"] = name
        if location != [0.0, 0.0, 0.0]:
            params["location"] = location
        if rotation != [0.0, 0.0, 0.0]:
            params["rotation"] = rotation
        if scale != [1.0, 1.0, 1.0]:
            params["scale"] = scale
        result = await bridge.send_command("mesh.add_primitive", params)
        return fmt("Add Primitive", result)

    @mcp.tool()
    async def blender_delete_objects(object_names: list[str]) -> str:
        """⚠️ Destructive: Delete specified objects from the Blender scene.

        Args:
            object_names: List of object names to delete.
        """
        result = await bridge.send_command(
            "mesh.delete", {"object_names": object_names}
        )
        return fmt("Delete Objects", result)

    @mcp.tool()
    async def blender_rename_object(old_name: str, new_name: str) -> str:
        """Rename an object in the Blender scene.

        Args:
            old_name: Current name of the object.
            new_name: New name for the object.
        """
        result = await bridge.send_command(
            "mesh.rename", {"old_name": old_name, "new_name": new_name}
        )
        return fmt("Rename", result)

    @mcp.tool()
    async def blender_transform(
        object_name: str,
        location: list[float] | None = None,
        rotation: list[float] | None = None,
        scale: list[float] | None = None,
    ) -> str:
        """Set the position, rotation, and/or scale of an object.

        Args:
            object_name: Name of the object to transform.
            location: [x, y, z] world position.
            rotation: [rx, ry, rz] rotation in radians.
            scale: [sx, sy, sz] scale.
        """
        params: dict = {"object_name": object_name}
        if location is not None:
            params["location"] = location
        if rotation is not None:
            params["rotation"] = rotation
        if scale is not None:
            params["scale"] = scale
        result = await bridge.send_command("mesh.transform", params)
        return fmt("Transform", result)

    @mcp.tool()
    async def blender_duplicate(
        object_name: str,
        new_name: str = "",
        offset: list[float] = [0.0, 0.0, 0.0],  # noqa: B006
    ) -> str:
        """Duplicate an object in the scene.

        Args:
            object_name: Name of the object to duplicate.
            new_name: Optional name for the copy.
            offset: [x, y, z] position offset from original.
        """
        params: dict = {"object_name": object_name}
        if new_name:
            params["new_name"] = new_name
        if offset != [0.0, 0.0, 0.0]:
            params["offset"] = offset
        result = await bridge.send_command("mesh.duplicate", params)
        return fmt("Duplicate", result)

    @mcp.tool()
    async def blender_join_objects(
        object_names: list[str],
        result_name: str = "",
    ) -> str:
        """Join multiple objects into a single mesh.

        Args:
            object_names: List of object names to join (minimum 2).
            result_name: Optional name for the resulting merged object.
        """
        params: dict = {"object_names": object_names}
        if result_name:
            params["result_name"] = result_name
        result = await bridge.send_command("mesh.join", params)
        return fmt("Join Objects", result)

    @mcp.tool()
    async def blender_set_smooth(
        object_name: str,
        smooth: bool = True,
    ) -> str:
        """Set smooth or flat shading on a mesh object.

        Args:
            object_name: Name of the mesh object.
            smooth: True for smooth shading, False for flat.
        """
        result = await bridge.send_command(
            "mesh.set_smooth",
            {"object_name": object_name, "smooth": smooth},
        )
        return fmt("Shading", result)
