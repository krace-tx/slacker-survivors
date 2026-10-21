"""Addon handler 公共工具函数。

将各 handler 中重复使用的 bpy 查询与格式化逻辑集中于此，
避免在每个领域 handler 中重复定义相同的工具函数。
"""
from __future__ import annotations

import bpy

from blender_mcp.shared.errors import BlenderMCPError, ErrorCode


def get_object(name: str) -> bpy.types.Object:
    """按名称获取 Blender 场景对象。

    Args:
        name: 对象名称（区分大小写，需与 Blender 中完全一致）。

    Returns:
        找到的 bpy.types.Object 实例。

    Raises:
        BlenderMCPError: 当对象不存在时，抛出 OBJECT_NOT_FOUND 错误。
    """
    obj = bpy.data.objects.get(name)
    if obj is None:
        raise BlenderMCPError(
            ErrorCode.OBJECT_NOT_FOUND,
            f"Object '{name}' not found in the current scene.",
            data={"requested_name": name},
        )
    return obj


def get_mesh_info(obj: bpy.types.Object) -> dict:
    """返回一个对象的摘要信息字典。

    包含名称、类型、变换信息；若对象为 MESH 类型，
    还会附加顶点数、面数、边数等拓扑统计。

    Args:
        obj: Blender 对象实例。

    Returns:
        包含对象信息的字典，可直接 JSON 序列化。
    """
    info: dict = {
        "name": obj.name,
        "type": obj.type,
        "location": [round(v, 4) for v in obj.location],
        "rotation": [round(v, 4) for v in obj.rotation_euler],
        "scale": [round(v, 4) for v in obj.scale],
    }
    if obj.type == "MESH" and obj.data:
        info["vertex_count"] = len(obj.data.vertices)
        info["face_count"] = len(obj.data.polygons)
        info["edge_count"] = len(obj.data.edges)
    return info
