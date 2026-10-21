"""网格操作命令：添加基本体、删除、重命名、变换、复制、合并、平滑着色。

所有涉及对象查找的操作统一使用 ``_helpers.get_object``。
"""

from __future__ import annotations

from typing import List, Optional

import bpy

from blender_mcp.shared.errors import BlenderMCPError, ErrorCode
from ..dispatcher import command
from ._helpers import get_object, get_mesh_info


@command("mesh.add_primitive")
def add_primitive(
    type: str = "cube",
    name: Optional[str] = None,
    location: Optional[List[float]] = None,
    rotation: Optional[List[float]] = None,
    scale: Optional[List[float]] = None,
    size: float = 1.0,
    segments: int = 32,
    rings: int = 16,
) -> dict:
    """向场景中添加一个基本体网格。

    Args:
        type: 基本体类型 — ``cube``、``sphere``、``ico_sphere``、
            ``cylinder``、``cone``、``torus``、``plane``、``circle``、
            ``monkey``、``grid``。
        name: 可选的自定义对象名称。
        location: ``[x, y, z]`` 世界坐标位置（默认 ``[0, 0, 0]``）。
        rotation: ``[rx, ry, rz]`` 旋转角度，单位弧度（默认 ``[0, 0, 0]``）。
        scale: ``[sx, sy, sz]`` 缩放（默认 ``[1, 1, 1]``）。
        size: 基本体的尺寸/半径。
        segments: 分段数（用于 sphere、cylinder 等）。
        rings: 环数（用于 sphere、torus）。

    Returns:
        新创建对象的网格信息字典。

    Raises:
        BlenderMCPError: 若 *type* 无法识别则抛出 ``INVALID_PARAMS``。
    """
    loc = tuple(location) if location else (0, 0, 0)
    rot = tuple(rotation) if rotation else (0, 0, 0)

    ptype = type.lower()
    if ptype == "cube":
        bpy.ops.mesh.primitive_cube_add(size=size, location=loc, rotation=rot)
    elif ptype in ("sphere", "uv_sphere"):
        bpy.ops.mesh.primitive_uv_sphere_add(
            radius=size / 2, segments=segments, ring_count=rings,
            location=loc, rotation=rot,
        )
    elif ptype == "ico_sphere":
        bpy.ops.mesh.primitive_ico_sphere_add(
            radius=size / 2, subdivisions=min(segments, 8),
            location=loc, rotation=rot,
        )
    elif ptype == "cylinder":
        bpy.ops.mesh.primitive_cylinder_add(
            radius=size / 2, depth=size, vertices=segments,
            location=loc, rotation=rot,
        )
    elif ptype == "cone":
        bpy.ops.mesh.primitive_cone_add(
            radius1=size / 2, depth=size, vertices=segments,
            location=loc, rotation=rot,
        )
    elif ptype == "torus":
        bpy.ops.mesh.primitive_torus_add(
            major_radius=size, minor_radius=size * 0.25,
            major_segments=segments, minor_segments=rings,
            location=loc, rotation=rot,
        )
    elif ptype == "plane":
        bpy.ops.mesh.primitive_plane_add(size=size, location=loc, rotation=rot)
    elif ptype == "circle":
        bpy.ops.mesh.primitive_circle_add(
            radius=size / 2, vertices=segments,
            location=loc, rotation=rot,
        )
    elif ptype == "monkey":
        bpy.ops.mesh.primitive_monkey_add(size=size, location=loc, rotation=rot)
    elif ptype == "grid":
        bpy.ops.mesh.primitive_grid_add(
            size=size, x_subdivisions=segments, y_subdivisions=segments,
            location=loc, rotation=rot,
        )
    else:
        raise BlenderMCPError(
            ErrorCode.INVALID_PARAMS,
            f"Unknown primitive type: '{type}'. Supported: cube, sphere, "
            f"ico_sphere, cylinder, cone, torus, plane, circle, monkey, grid",
            {"type": type},
        )

    obj = bpy.context.active_object
    if name:
        obj.name = name
        if obj.data:
            obj.data.name = name

    if scale:
        obj.scale = tuple(scale)

    return get_mesh_info(obj)


@command("mesh.delete")
def delete(object_names: List[str]) -> dict:
    """⚠️ 破坏性操作：删除指定的网格对象。

    Args:
        object_names: 要删除的对象名称列表。

    Returns:
        包含 *deleted* 和 *not_found* 列表的字典。
    """
    bpy.ops.object.select_all(action="DESELECT")
    deleted: list[str] = []
    not_found: list[str] = []
    for oname in object_names:
        obj = bpy.data.objects.get(oname)
        if obj:
            obj.select_set(True)
            deleted.append(oname)
        else:
            not_found.append(oname)

    if deleted:
        bpy.ops.object.delete()

    return {
        "deleted": deleted,
        "not_found": not_found,
    }


@command("mesh.rename")
def rename(old_name: str, new_name: str) -> dict:
    """重命名一个对象。

    Args:
        old_name: 当前对象名称。
        new_name: 期望的新对象名称。

    Returns:
        包含 *old_name* 和 *new_name* 的字典（Blender 可能会在冲突时添加后缀）。

    Raises:
        BlenderMCPError: 若 *old_name* 不存在则抛出 ``OBJECT_NOT_FOUND``。
    """
    obj = get_object(old_name)
    obj.name = new_name
    if obj.data:
        obj.data.name = new_name
    return {"old_name": old_name, "new_name": obj.name}


@command("mesh.transform")
def transform(
    object_name: str,
    location: Optional[List[float]] = None,
    rotation: Optional[List[float]] = None,
    scale: Optional[List[float]] = None,
) -> dict:
    """设置对象的变换属性。

    Args:
        object_name: 对象名称。
        location: ``[x, y, z]`` 世界坐标位置。
        rotation: ``[rx, ry, rz]`` 旋转角度，单位弧度。
        scale: ``[sx, sy, sz]`` 缩放。

    Returns:
        更新后的网格信息字典。

    Raises:
        BlenderMCPError: 若 *object_name* 不存在则抛出 ``OBJECT_NOT_FOUND``。
    """
    obj = get_object(object_name)
    if location:
        obj.location = tuple(location)
    if rotation:
        obj.rotation_euler = tuple(rotation)
    if scale:
        obj.scale = tuple(scale)
    return get_mesh_info(obj)


@command("mesh.duplicate")
def duplicate(
    object_name: str,
    new_name: Optional[str] = None,
    offset: Optional[List[float]] = None,
) -> dict:
    """复制一个对象。

    Args:
        object_name: 要复制的对象名称。
        new_name: 可选的新对象名称。
        offset: ``[x, y, z]`` 相对原位置的偏移量。

    Returns:
        复制后对象的网格信息字典。

    Raises:
        BlenderMCPError: 若 *object_name* 不存在则抛出 ``OBJECT_NOT_FOUND``。
    """
    obj = get_object(object_name)
    new_obj = obj.copy()
    if obj.data:
        new_obj.data = obj.data.copy()
    bpy.context.collection.objects.link(new_obj)

    if new_name:
        new_obj.name = new_name
        if new_obj.data:
            new_obj.data.name = new_name

    if offset:
        new_obj.location.x += offset[0]
        new_obj.location.y += offset[1]
        new_obj.location.z += offset[2]

    return get_mesh_info(new_obj)


@command("mesh.join")
def join(object_names: List[str], result_name: Optional[str] = None) -> dict:
    """合并多个对象为一个。

    Args:
        object_names: 要合并的对象名称列表（至少 2 个）。
        result_name: 可选的合并后对象名称。

    Returns:
        合并后对象的网格信息字典。

    Raises:
        BlenderMCPError: 若名称数量少于 2 个则抛出 ``INVALID_PARAMS``。
        BlenderMCPError: 若任何名称不存在则抛出 ``OBJECT_NOT_FOUND``。
    """
    if len(object_names) < 2:
        raise BlenderMCPError(
            ErrorCode.INVALID_PARAMS,
            "Need at least 2 objects to join",
            {"count": len(object_names)},
        )

    bpy.ops.object.select_all(action="DESELECT")
    for oname in object_names:
        obj = get_object(oname)
        obj.select_set(True)

    bpy.context.view_layer.objects.active = bpy.data.objects[object_names[0]]
    bpy.ops.object.join()

    result = bpy.context.active_object
    if result_name:
        result.name = result_name
        if result.data:
            result.data.name = result_name

    return get_mesh_info(result)


@command("mesh.set_smooth")
def set_smooth(object_name: str, smooth: bool = True) -> dict:
    """设置网格对象的平滑或平面着色。

    Args:
        object_name: 对象名称。
        smooth: ``True`` 为平滑着色，``False`` 为平面着色。

    Returns:
        包含 *object* 和 *smooth* 状态的字典。

    Raises:
        BlenderMCPError: 若 *object_name* 不存在则抛出 ``OBJECT_NOT_FOUND``。
        BlenderMCPError: 若对象不是网格则抛出 ``INVALID_MODE``。
    """
    obj = get_object(object_name)
    if obj.type != "MESH":
        raise BlenderMCPError(
            ErrorCode.INVALID_MODE,
            f"Object '{object_name}' is not a mesh (type: {obj.type})",
            {"object": object_name, "actual_type": obj.type},
        )

    for polygon in obj.data.polygons:
        polygon.use_smooth = smooth
    obj.data.update()

    return {"object": object_name, "smooth": smooth}
