"""修改器 Tools：添加、应用、移除、列出。"""
from __future__ import annotations

from typing import Any

from ..utils import call
from ._group import ToolGroup

modifier_tools = ToolGroup("modifier")


@modifier_tools.tool()
async def blender_add_modifier(
    object_name: str,
    type: str = "SUBSURF",
    name: str | None = None,
    properties: dict[str, Any] | None = None,
) -> str:
    """Add a modifier to an object.

    Args:
        object_name: Target object.
        type: SUBSURF, MIRROR, BOOLEAN, SOLIDIFY, ARRAY, BEVEL, DECIMATE, SMOOTH, WEIGHTED_NORMAL,
            SHRINKWRAP, SIMPLE_DEFORM ...
        name: Custom modifier name.
        properties: Modifier properties, e.g. {"levels": 2} for SUBSURF, {"count": 5} for ARRAY,
            {"operation": "DIFFERENCE", "object": "Cutter"} for BOOLEAN (object refs accept names).
            Unknown or invalid properties are reported back in 'ignored_properties'.
    """
    return await call("Add Modifier", "modifier.add", object_name=object_name, type=type,
                      name=name, properties=properties)


@modifier_tools.tool(destructive=True)
async def blender_apply_modifier(object_name: str, modifier_name: str) -> str:
    """Apply (bake) a modifier permanently onto the mesh.

    Args:
        object_name: Target object.
        modifier_name: Modifier to apply.
    """
    return await call("Apply Modifier", "modifier.apply", object_name=object_name, modifier_name=modifier_name)


@modifier_tools.tool(destructive=True)
async def blender_remove_modifier(object_name: str, modifier_name: str) -> str:
    """Remove a modifier from an object.

    Args:
        object_name: Target object.
        modifier_name: Modifier to remove.
    """
    return await call("Remove Modifier", "modifier.remove", object_name=object_name, modifier_name=modifier_name)


@modifier_tools.tool(read_only=True)
async def blender_list_modifiers(object_name: str) -> str:
    """List all modifiers on an object with their key properties.

    Args:
        object_name: Target object.
    """
    return await call("Modifiers", "modifier.list", object_name=object_name)
