"""修改器管理命令：为对象添加、应用、移除修改器，以及列出对象上的修改器。"""

from __future__ import annotations

from typing import Any, Optional

import bpy

from blender_mcp.shared.errors import BlenderMCPError, ErrorCode
from ..dispatcher import command
from ._helpers import get_object


@command("modifier.add")
def add_modifier(
    object_name: str,
    type: str = "SUBSURF",
    name: Optional[str] = None,
    **kwargs: Any,
) -> dict:
    """为对象添加一个修改器。

    Args:
        object_name: 目标对象名称。
        type: 修改器类型 — ``SUBSURF``、``MIRROR``、``BOOLEAN``、
            ``SOLIDIFY``、``ARRAY``、``BEVEL``、``DECIMATE``、``SMOOTH``、
            ``SHRINKWRAP``、``SIMPLE_DEFORM`` 等。
        name: 可选的自定义修改器名称。
        **kwargs: 修改器特有的额外属性
            （例如为 ``SUBSURF`` 设置 ``levels=2``）。

    Returns:
        包含修改器详情和关键类型属性的字典。

    Raises:
        BlenderMCPError: 若 *object_name* 不存在则抛出 ``OBJECT_NOT_FOUND``。
    """
    obj = get_object(object_name)
    mod_name = name or type.title()
    mod = obj.modifiers.new(name=mod_name, type=type.upper())
    for k, v in kwargs.items():
        if hasattr(mod, k):
            setattr(mod, k, v)

    result: dict = {
        "object": object_name,
        "modifier": mod.name,
        "type": mod.type,
    }
    # 根据类型报告关键属性
    if mod.type == "SUBSURF":
        result["levels"] = mod.levels
        result["render_levels"] = mod.render_levels
    elif mod.type == "MIRROR":
        result["use_axis"] = [mod.use_axis[0], mod.use_axis[1], mod.use_axis[2]]
    elif mod.type == "ARRAY":
        result["count"] = mod.count
    elif mod.type == "SOLIDIFY":
        result["thickness"] = mod.thickness
    elif mod.type == "BEVEL":
        result["width"] = mod.width
        result["segments"] = mod.segments
    return result


@command("modifier.apply")
def apply_modifier(object_name: str, modifier_name: str) -> dict:
    """永久应用（烘焙）一个修改器。

    Args:
        object_name: 目标对象名称。
        modifier_name: 要应用的修改器名称。

    Returns:
        包含 *object*、已应用的 *applied* 修改器名称和网格计数的字典。

    Raises:
        BlenderMCPError: 若对象或修改器未找到则抛出 ``OBJECT_NOT_FOUND``。
    """
    obj = get_object(object_name)
    if modifier_name not in [m.name for m in obj.modifiers]:
        raise BlenderMCPError(
            ErrorCode.OBJECT_NOT_FOUND,
            f"Modifier '{modifier_name}' not found on '{object_name}'",
            {"object": object_name, "modifier": modifier_name},
        )
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=modifier_name)

    info: dict = {"object": object_name, "applied": modifier_name}
    if obj.type == "MESH":
        info["vertex_count"] = len(obj.data.vertices)
        info["face_count"] = len(obj.data.polygons)
    return info


@command("modifier.remove")
def remove_modifier(object_name: str, modifier_name: str) -> dict:
    """从对象上移除一个修改器。

    Args:
        object_name: 目标对象名称。
        modifier_name: 要移除的修改器名称。

    Returns:
        包含 *object* 和已移除的 *removed* 修改器名称的字典。

    Raises:
        BlenderMCPError: 若对象或修改器未找到则抛出 ``OBJECT_NOT_FOUND``。
    """
    obj = get_object(object_name)
    mod = obj.modifiers.get(modifier_name)
    if mod is None:
        raise BlenderMCPError(
            ErrorCode.OBJECT_NOT_FOUND,
            f"Modifier '{modifier_name}' not found on '{object_name}'",
            {"object": object_name, "modifier": modifier_name},
        )
    obj.modifiers.remove(mod)
    return {"object": object_name, "removed": modifier_name}


@command("modifier.list")
def list_modifiers(object_name: str) -> dict:
    """列出对象上的所有修改器。

    Args:
        object_name: 目标对象名称。

    Returns:
        包含 *object*、*modifiers* 列表和 *count* 的字典。

    Raises:
        BlenderMCPError: 若 *object_name* 不存在则抛出 ``OBJECT_NOT_FOUND``。
    """
    obj = get_object(object_name)
    mods: list[dict] = []
    for mod in obj.modifiers:
        mods.append({
            "name": mod.name,
            "type": mod.type,
            "show_viewport": mod.show_viewport,
            "show_render": mod.show_render,
        })
    return {"object": object_name, "modifiers": mods, "count": len(mods)}
