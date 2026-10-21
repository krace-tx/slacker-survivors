"""摄像机和灯光管理命令：创建相机、指向目标、设置活动相机、创建灯光、设置 HDRI。"""

from __future__ import annotations

from typing import List, Optional

import bpy

from blender_mcp.shared.errors import BlenderMCPError, ErrorCode
from ..dispatcher import command
from ._helpers import get_object


@command("camera.create")
def create_camera(
    name: str = "Camera",
    location: Optional[List[float]] = None,
    rotation: Optional[List[float]] = None,
    lens: float = 50.0,
    type: str = "PERSP",
) -> dict:
    """创建一个摄像机。

    Args:
        name: 摄像机名称。
        location: ``[x, y, z]`` 位置。
        rotation: ``[rx, ry, rz]`` 旋转角度，单位弧度。
        lens: 焦距，单位毫米（默认 50）。
        type: ``PERSP``（透视）或 ``ORTHO``（正交）。

    Returns:
        包含摄像机属性的字典。
    """
    cam_data = bpy.data.cameras.new(name=name)
    cam_data.lens = lens
    cam_data.type = type.upper()
    cam_obj = bpy.data.objects.new(name=name, object_data=cam_data)
    bpy.context.collection.objects.link(cam_obj)
    if location:
        cam_obj.location = tuple(location)
    if rotation:
        cam_obj.rotation_euler = tuple(rotation)
    return {
        "name": cam_obj.name,
        "type": cam_data.type,
        "lens": cam_data.lens,
        "location": [round(v, 4) for v in cam_obj.location],
        "rotation": [round(v, 4) for v in cam_obj.rotation_euler],
    }


@command("camera.look_at")
def look_at(camera_name: str, target: List[float]) -> dict:
    """将摄像机指向目标位置。

    Args:
        camera_name: 摄像机对象的名称。
        target: ``[x, y, z]`` 要朝向的目标点。

    Returns:
        包含 *camera*、*target* 和计算得到的 *rotation* 的字典。

    Raises:
        BlenderMCPError: 若 *camera_name* 不存在则抛出 ``OBJECT_NOT_FOUND``。
    """
    import mathutils

    cam = get_object(camera_name)
    target_vec = mathutils.Vector(target)
    direction = target_vec - cam.location
    rot_quat = direction.to_track_quat("-Z", "Y")
    cam.rotation_euler = rot_quat.to_euler()
    return {
        "camera": camera_name,
        "target": target,
        "rotation": [round(v, 4) for v in cam.rotation_euler],
    }


@command("camera.set_active")
def set_active_camera(camera_name: str) -> dict:
    """设置场景的活动摄像机。

    Args:
        camera_name: 摄像机对象的名称。

    Returns:
        包含 *active_camera* 名称的字典。

    Raises:
        BlenderMCPError: 若 *camera_name* 不存在则抛出 ``OBJECT_NOT_FOUND``。
        BlenderMCPError: 若对象不是摄像机则抛出 ``INVALID_MODE``。
    """
    cam = get_object(camera_name)
    if cam.type != "CAMERA":
        raise BlenderMCPError(
            ErrorCode.INVALID_MODE,
            f"'{camera_name}' is not a camera (type: {cam.type})",
            {"object": camera_name, "actual_type": cam.type},
        )
    bpy.context.scene.camera = cam
    return {"active_camera": camera_name}


@command("light.create")
def create_light(
    name: str = "Light",
    type: str = "POINT",
    location: Optional[List[float]] = None,
    energy: float = 1000.0,
    color: Optional[List[float]] = None,
    radius: float = 0.25,
) -> dict:
    """创建一个光源。

    Args:
        name: 灯光名称。
        type: ``POINT``（点光）、``SUN``（日光）、``SPOT``（聚光）或 ``AREA``（面光）。
        location: ``[x, y, z]`` 位置。
        energy: 灯光功率，单位瓦特。
        color: ``[r, g, b]`` 灯光颜色（0.0–1.0）。
        radius: 灯光半径，用于柔和阴影。

    Returns:
        包含灯光属性的字典。
    """
    light_data = bpy.data.lights.new(name=name, type=type.upper())
    light_data.energy = energy
    if color:
        light_data.color = tuple(color[:3])
    light_data.shadow_soft_size = radius
    light_obj = bpy.data.objects.new(name=name, object_data=light_data)
    bpy.context.collection.objects.link(light_obj)
    if location:
        light_obj.location = tuple(location)
    return {
        "name": light_obj.name,
        "type": light_data.type,
        "energy": light_data.energy,
        "color": list(light_data.color),
        "location": [round(v, 4) for v in light_obj.location],
    }


@command("light.set_world_hdri")
def set_world_hdri(hdri_path: str, strength: float = 1.0) -> dict:
    """为世界环境设置 HDRI 环境贴图。

    Args:
        hdri_path: ``.hdr`` 或 ``.exr`` 文件的绝对路径。
        strength: 背景强度（默认 1.0）。

    Returns:
        包含 *hdri* 路径和 *strength* 的字典。
    """
    world = bpy.context.scene.world
    if world is None:
        world = bpy.data.worlds.new(name="World")
        bpy.context.scene.world = world
    world.use_nodes = True
    tree = world.node_tree
    tree.nodes.clear()
    # 创建节点
    tex_coord = tree.nodes.new("ShaderNodeTexCoord")
    mapping = tree.nodes.new("ShaderNodeMapping")
    env_tex = tree.nodes.new("ShaderNodeTexEnvironment")
    bg = tree.nodes.new("ShaderNodeBackground")
    output = tree.nodes.new("ShaderNodeOutputWorld")
    # 加载图片
    env_tex.image = bpy.data.images.load(hdri_path)
    bg.inputs["Strength"].default_value = strength
    # 连接节点
    tree.links.new(tex_coord.outputs["Generated"], mapping.inputs["Vector"])
    tree.links.new(mapping.outputs["Vector"], env_tex.inputs["Vector"])
    tree.links.new(env_tex.outputs["Color"], bg.inputs["Color"])
    tree.links.new(bg.outputs["Background"], output.inputs["Surface"])
    return {"hdri": hdri_path, "strength": strength}
