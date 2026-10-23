"""对象与网格建模 Tools：基本体、删除、重命名、变换、复制、合并、着色。"""
from __future__ import annotations

from ..utils import call
from ._group import ToolGroup

modeling_tools = ToolGroup("modeling")


@modeling_tools.tool(read_only=True)
async def blender_object_info(object_name: str) -> str:
    """Get detailed info of one object: transform, dimensions, topology counts, materials, modifiers.

    Args:
        object_name: Object name.
    """
    return await call("Object Info", "object.get_info", object_name=object_name)


@modeling_tools.tool()
async def blender_add_primitive(
    type: str = "cube",
    name: str | None = None,
    location: list[float] | None = None,
    rotation: list[float] | None = None,
    scale: list[float] | None = None,
    size: float | None = None,
    segments: int | None = None,
    rings: int | None = None,
) -> str:
    """Add a primitive mesh object to the scene.

    Args:
        type: cube, sphere, ico_sphere, cylinder, cone, torus, plane, circle, monkey, grid.
        name: Custom object name. Omit for Blender's default.
        location: [x, y, z] world position. Default [0, 0, 0].
        rotation: [rx, ry, rz] Euler rotation in radians. Default [0, 0, 0].
        scale: [sx, sy, sz]. Default [1, 1, 1].
        size: Size / diameter. Default 1.0.
        segments: Segments for curved primitives. Default 32.
        rings: Rings for sphere / torus. Default 16.
    """
    return await call("Add Primitive", "mesh.add_primitive", type=type, name=name, location=location,
                      rotation=rotation, scale=scale, size=size, segments=segments, rings=rings)


@modeling_tools.tool(destructive=True)
async def blender_delete_objects(object_names: list[str]) -> str:
    """⚠️ Destructive: delete objects by name.

    Args:
        object_names: Names of objects to delete.
    """
    return await call("Delete Objects", "object.delete", object_names=object_names)


@modeling_tools.tool()
async def blender_rename_object(old_name: str, new_name: str) -> str:
    """Rename an object. Blender may append a suffix (.001) on name conflicts; the real name is returned.

    Args:
        old_name: Current object name.
        new_name: New object name.
    """
    return await call("Rename", "object.rename", old_name=old_name, new_name=new_name)


@modeling_tools.tool(idempotent=True)
async def blender_transform(
    object_name: str,
    location: list[float] | None = None,
    rotation: list[float] | None = None,
    scale: list[float] | None = None,
) -> str:
    """Set location / rotation / scale of an object. Omitted fields stay unchanged.

    Args:
        object_name: Object name.
        location: [x, y, z] world position.
        rotation: [rx, ry, rz] Euler rotation in radians.
        scale: [sx, sy, sz].
    """
    return await call("Transform", "object.transform", object_name=object_name,
                      location=location, rotation=rotation, scale=scale)


@modeling_tools.tool()
async def blender_duplicate(
    object_name: str,
    new_name: str | None = None,
    offset: list[float] | None = None,
    linked: bool = False,
) -> str:
    """Duplicate an object.

    Args:
        object_name: Object to duplicate.
        new_name: Name of the copy.
        offset: [x, y, z] offset from the original position.
        linked: Share mesh data with the original instead of deep-copying it.
    """
    return await call("Duplicate", "object.duplicate", object_name=object_name,
                      new_name=new_name, offset=offset, linked=linked)


@modeling_tools.tool()
async def blender_join_objects(object_names: list[str], result_name: str | None = None) -> str:
    """Join multiple mesh objects into one. The first object is the join target.

    Args:
        object_names: At least 2 mesh object names.
        result_name: Name of the merged object.
    """
    return await call("Join Objects", "object.join", object_names=object_names, result_name=result_name)


@modeling_tools.tool(idempotent=True)
async def blender_set_smooth(object_name: str, smooth: bool = True) -> str:
    """Set smooth or flat shading on a mesh object.

    Args:
        object_name: Mesh object name.
        smooth: True for smooth shading, False for flat.
    """
    return await call("Shading", "mesh.set_smooth", object_name=object_name, smooth=smooth)
