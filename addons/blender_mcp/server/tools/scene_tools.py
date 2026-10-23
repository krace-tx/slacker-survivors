"""场景管理 Tools：场景信息、对象列表、清空、选择、撤销 / 重做。"""
from __future__ import annotations

from ..utils import call
from ._group import ToolGroup

scene_tools = ToolGroup("scene")


@scene_tools.tool(read_only=True)
async def blender_scene_info() -> str:
    """Get current scene info: name, frame range, FPS, render engine, resolution, active camera, selection."""
    return await call("Scene Info", "scene.get_info")


@scene_tools.tool(read_only=True)
async def blender_list_objects(type_filter: str | None = None) -> str:
    """List all objects in the current scene with transform, dimensions, materials and modifiers.

    Args:
        type_filter: Only list this type: MESH, CURVE, ARMATURE, EMPTY, CAMERA, LIGHT ... Omit for all.
    """
    return await call("Scene Objects", "scene.list_objects", type_filter=type_filter)


@scene_tools.tool(destructive=True)
async def blender_clear_scene(type_filter: str = "MESH") -> str:
    """⚠️ Destructive: delete objects from the scene by type.

    Args:
        type_filter: Object type to delete (MESH, CAMERA, LIGHT, EMPTY ...) or ALL.
    """
    return await call("Clear Scene", "scene.clear", type_filter=type_filter)


@scene_tools.tool()
async def blender_select(
    object_names: list[str] | None = None,
    select_all: bool = False,
    deselect_all: bool = False,
    replace: bool = False,
) -> str:
    """Select or deselect objects. The first found object in object_names becomes active.

    Args:
        object_names: Objects to select.
        select_all: Select every object.
        deselect_all: Deselect every object.
        replace: Clear the existing selection before selecting object_names.
    """
    if deselect_all or select_all:
        return await call("Selection", "scene.select", all=True, deselect=deselect_all)
    return await call("Selection", "scene.select", object_names=object_names or [], replace=replace)


@scene_tools.tool()
async def blender_undo() -> str:
    """Undo the last operation in Blender (Ctrl+Z). Every MCP write operation is one undo step."""
    return await call("Undo", "scene.undo")


@scene_tools.tool()
async def blender_redo() -> str:
    """Redo the last undone operation in Blender (Ctrl+Shift+Z)."""
    return await call("Redo", "scene.redo")
