"""场景级别的命令：列出对象、获取场景信息、清空场景、选择对象、撤销/重做。

这些命令不操作单个对象属性，而是作用于整个场景状态。
"""

from __future__ import annotations

from typing import List, Optional

import bpy

from blender_mcp.shared.errors import BlenderMCPError, ErrorCode
from ..dispatcher import command


@command("scene.list_objects")
def list_objects(type_filter: Optional[str] = None) -> dict:
    """列出当前场景中的所有对象。

    Args:
        type_filter: 可选的对象类型过滤器
            （``MESH``、``ARMATURE``、``CAMERA``、``LIGHT``、``EMPTY`` 等）。

    Returns:
        包含 *count* 和 *objects* 列表的字典。
    """
    objects: list[dict] = []
    for obj in bpy.context.scene.objects:
        if type_filter and obj.type != type_filter.upper():
            continue
        obj_info: dict = {
            "name": obj.name,
            "type": obj.type,
            "location": [round(v, 4) for v in obj.location],
            "rotation": [round(v, 4) for v in obj.rotation_euler],
            "scale": [round(v, 4) for v in obj.scale],
            "visible": obj.visible_get(),
        }
        if obj.type == "MESH":
            obj_info["vertex_count"] = len(obj.data.vertices)
            obj_info["face_count"] = len(obj.data.polygons)
            obj_info["edge_count"] = len(obj.data.edges)
        objects.append(obj_info)

    return {
        "count": len(objects),
        "objects": objects,
    }


@command("scene.get_info")
def get_info() -> dict:
    """获取当前场景信息。

    Returns:
        包含场景名称、帧范围、FPS、渲染引擎、对象数量、
        已选择对象和活动对象的字典。
    """
    scene = bpy.context.scene
    return {
        "name": scene.name,
        "frame_start": scene.frame_start,
        "frame_end": scene.frame_end,
        "frame_current": scene.frame_current,
        "fps": scene.render.fps,
        "render_engine": scene.render.engine,
        "object_count": len(scene.objects),
        "selected_objects": [obj.name for obj in bpy.context.selected_objects],
        "active_object": (
            bpy.context.active_object.name if bpy.context.active_object else None
        ),
    }


@command("scene.clear")
def clear(type_filter: str = "MESH", confirm: bool = True) -> dict:
    """⚠️ 破坏性操作：从场景中清除对象。

    Args:
        type_filter: 要清除的对象类型。``'ALL'`` 清除所有对象，
            或指定具体类型如 ``'MESH'``。
        confirm: 必须为 ``True`` 才会执行（安全校验）。

    Returns:
        包含 *status*、*deleted_count* 和 *deleted_objects* 的字典。
    """
    if not confirm:
        return {"status": "cancelled", "message": "Set confirm=True to proceed"}

    bpy.ops.object.select_all(action="DESELECT")
    deleted: list[str] = []
    for obj in list(bpy.context.scene.objects):
        if type_filter == "ALL" or obj.type == type_filter.upper():
            deleted.append(obj.name)
            obj.select_set(True)

    if deleted:
        bpy.ops.object.delete()

    return {
        "status": "success",
        "deleted_count": len(deleted),
        "deleted_objects": deleted,
    }


@command("scene.select")
def select(
    object_names: Optional[List[str]] = None,
    all: bool = False,
    deselect: bool = False,
) -> dict:
    """选择或取消选择场景中的对象。

    Args:
        object_names: 要选择的对象名称列表。
        all: 若为 ``True``，则选择所有对象。
        deselect: 若为 ``True``，则取消选择而非选择。

    Returns:
        包含 *status* 和操作详情的字典。
    """
    if deselect or all:
        bpy.ops.object.select_all(action="DESELECT" if deselect else "SELECT")
        if deselect:
            return {"status": "success", "action": "deselect_all"}
        return {"status": "success", "action": "select_all"}

    selected: list[str] = []
    not_found: list[str] = []
    for name in object_names or []:
        obj = bpy.data.objects.get(name)
        if obj:
            obj.select_set(True)
            bpy.context.view_layer.objects.active = obj
            selected.append(name)
        else:
            not_found.append(name)

    return {
        "status": "success",
        "selected": selected,
        "not_found": not_found,
    }


@command("scene.undo")
def undo() -> dict:
    """撤销上一步操作。

    Returns:
        包含 *status* 和确认 *message* 的字典。
    """
    bpy.ops.ed.undo()
    return {"status": "success", "message": "Undo performed"}


@command("scene.redo")
def redo() -> dict:
    """重做上一步被撤销的操作。

    Returns:
        包含 *status* 和确认 *message* 的字典。
    """
    bpy.ops.ed.redo()
    return {"status": "success", "message": "Redo performed"}
