"""材质管理命令：创建材质、分配给对象、设置颜色、列出和删除材质。"""

from __future__ import annotations

from typing import List, Optional

import bpy

from blender_mcp.shared.errors import BlenderMCPError, ErrorCode
from ..dispatcher import command
from ._helpers import get_object


@command("material.create")
def create_material(
    name: str,
    color: Optional[List[float]] = None,
    metallic: float = 0.0,
    roughness: float = 0.5,
    use_nodes: bool = True,
) -> dict:
    """创建一个新材质。

    Args:
        name: 材质名称。
        color: ``[r, g, b, a]`` 基础颜色（0.0–1.0 范围），默认白色。
        metallic: 金属度（0.0–1.0）。
        roughness: 粗糙度（0.0–1.0）。
        use_nodes: 是否使用着色器节点（默认 ``True``）。

    Returns:
        包含材质属性的字典。
    """
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = use_nodes
    if use_nodes and mat.node_tree:
        bsdf = mat.node_tree.nodes.get("Principled BSDF")
        if bsdf:
            if color:
                c = color if len(color) == 4 else color + [1.0]
                bsdf.inputs["Base Color"].default_value = tuple(c)
            bsdf.inputs["Metallic"].default_value = metallic
            bsdf.inputs["Roughness"].default_value = roughness
    return {
        "name": mat.name,
        "use_nodes": mat.use_nodes,
        "color": color or [0.8, 0.8, 0.8, 1.0],
        "metallic": metallic,
        "roughness": roughness,
    }


@command("material.assign")
def assign_material(object_name: str, material_name: str) -> dict:
    """将材质分配给对象。

    Args:
        object_name: 目标对象名称。
        material_name: 已有材质的名称。

    Returns:
        包含 *object* 和 *material* 名称的字典。

    Raises:
        BlenderMCPError: 若对象或材质未找到则抛出 ``OBJECT_NOT_FOUND``。
    """
    obj = get_object(object_name)
    mat = bpy.data.materials.get(material_name)
    if mat is None:
        raise BlenderMCPError(
            ErrorCode.OBJECT_NOT_FOUND,
            f"Material '{material_name}' not found",
            {"material": material_name},
        )
    if obj.data.materials:
        obj.data.materials[0] = mat
    else:
        obj.data.materials.append(mat)
    return {"object": object_name, "material": mat.name}


@command("material.set_color")
def set_color(object_name: str, color: List[float]) -> dict:
    """设置对象上第一个材质的基础颜色。

    若对象没有材质，会自动创建一个新材质。

    Args:
        object_name: 目标对象名称。
        color: ``[r, g, b]`` 或 ``[r, g, b, a]`` 颜色值（0.0–1.0）。

    Returns:
        包含 *object*、*material* 和 *color* 的字典。

    Raises:
        BlenderMCPError: 若 *object_name* 不存在则抛出 ``OBJECT_NOT_FOUND``。
    """
    obj = get_object(object_name)
    if not obj.data.materials:
        mat = bpy.data.materials.new(name=f"{object_name}_Material")
        mat.use_nodes = True
        obj.data.materials.append(mat)
    mat = obj.data.materials[0]
    if mat.use_nodes and mat.node_tree:
        bsdf = mat.node_tree.nodes.get("Principled BSDF")
        if bsdf:
            c = color if len(color) == 4 else color + [1.0]
            bsdf.inputs["Base Color"].default_value = tuple(c)
    return {"object": object_name, "material": mat.name, "color": color}


@command("material.list")
def list_materials() -> dict:
    """列出当前 blend 文件中的所有材质。

    Returns:
        包含 *materials* 列表和 *count* 的字典。
    """
    mats: list[dict] = []
    for mat in bpy.data.materials:
        info: dict = {
            "name": mat.name,
            "use_nodes": mat.use_nodes,
            "users": mat.users,
        }
        if mat.use_nodes and mat.node_tree:
            bsdf = mat.node_tree.nodes.get("Principled BSDF")
            if bsdf:
                info["base_color"] = list(bsdf.inputs["Base Color"].default_value)
        mats.append(info)
    return {"materials": mats, "count": len(mats)}


@command("material.delete")
def delete_material(material_name: str) -> dict:
    """按名称删除一个材质。

    Args:
        material_name: 要删除的材质名称。

    Returns:
        包含已删除的 *deleted* 材质名称的字典。

    Raises:
        BlenderMCPError: 若材质未找到则抛出 ``OBJECT_NOT_FOUND``。
    """
    mat = bpy.data.materials.get(material_name)
    if mat is None:
        raise BlenderMCPError(
            ErrorCode.OBJECT_NOT_FOUND,
            f"Material '{material_name}' not found",
            {"material": material_name},
        )
    bpy.data.materials.remove(mat)
    return {"deleted": material_name}
