#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
render_lookdev_card.py
工业级 Blender 单体资产/角色/场地 摄影棚 LookDev 预览卡渲染器。

功能：
1. 在不破坏原 .blend 文件的前提下，自动计算目标资产的世界空间包围盒 (AABB)；
2. 搭建标准三点柔光摄影棚（暖主光 Key + 冷辅光 Fill + 轮廓光 Rim + 柔和浅灰摄影棚背景）；
3. 自动架设正交/透视相机渲染 Front（正视）、Side（侧视）、Iso34（45°轴测主视）三张高清图；
4. 使用 Blender 内置 bpy.data.images 像素缓冲将三张视图横向拼接为一张 1920x640 的
   `<asset_name>_lookdev_card.png` 三合一效果图卡，供 AI Agent 与 2D 概念图直接比对。

调用方式：
  /Applications/Blender.app/Contents/MacOS/Blender -b <path/to/asset.blend> \
      --python .agents/skills/blender-pipeline/scripts/render_lookdev_card.py -- \
      --out-dir <path/to/renders> --name <asset_name>
"""

import os
import sys
import math
import bpy
from mathutils import Vector


def parse_args():
    argv = sys.argv
    if "--" in argv:
        argv = argv[argv.index("--") + 1:]
    else:
        argv = []

    out_dir = None
    name = "asset"
    res = 640
    i = 0
    while i < len(argv):
        if argv[i] in ("--out-dir", "--output-dir") and i + 1 < len(argv):
            out_dir = argv[i + 1]
            i += 2
        elif argv[i] in ("--name", "--asset-name") and i + 1 < len(argv):
            name = argv[i + 1]
            i += 2
        elif argv[i] in ("--res", "--resolution") and i + 1 < len(argv):
            res = int(argv[i + 1])
            i += 2
        else:
            i += 1
    return out_dir, name, res


def compute_scene_aabb(mesh_objects):
    min_co = Vector((1e9, 1e9, 1e9))
    max_co = Vector((-1e9, -1e9, -1e9))
    for obj in mesh_objects:
        for corner in obj.bound_box:
            w = obj.matrix_world @ Vector(corner)
            min_co.x = min(min_co.x, w.x)
            min_co.y = min(min_co.y, w.y)
            min_co.z = min(min_co.z, w.z)
            max_co.x = max(max_co.x, w.x)
            max_co.y = max(max_co.y, w.y)
            max_co.z = max(max_co.z, w.z)
    return min_co, max_co


def setup_studio_lighting(center, max_span, min_z=0.0):
    """配置标准无影棚三点布光、浅灰背景与接触阴影地面。"""
    scene = bpy.context.scene
    if not scene.world:
        scene.world = bpy.data.worlds.new("LookDevWorld")
    bg = scene.world.node_tree.nodes.get("Background")
    if bg:
        bg.inputs["Color"].default_value = (0.86, 0.87, 0.89, 1.0)
        bg.inputs["Strength"].default_value = 0.85

    # 隐藏原有灯光，使用标准摄影棚灯光确保不同资产对比一致性
    for obj in list(bpy.data.objects):
        if obj.type == 'LIGHT':
            obj.hide_render = True

    # 创建浅灰柔光摄影棚地面圆盘以接收接触阴影 (Contact Shadow)
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=64,
        radius=max_span * 3.5,
        depth=0.02,
        location=(center.x, center.y, min_z - 0.011),
    )
    floor_obj = bpy.context.active_object
    floor_obj.name = "__LookDev_Floor"
    floor_mat = bpy.data.materials.new("__LookDev_FloorMat")
    bsdf = floor_mat.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = (0.78, 0.80, 0.82, 1.0)
        bsdf.inputs["Roughness"].default_value = 0.85
    floor_obj.data.materials.append(floor_mat)

    dist = max(max_span * 2.5, 2.5)

    # 1. Key Light (暖白主柔光 + 阴影)
    key_data = bpy.data.lights.new(name="__LookDev_Key", type='SUN')
    key_data.energy = 3.4
    key_data.color = (1.0, 0.97, 0.92)
    key_data.angle = math.radians(12.0)
    key_data.use_shadow = True
    key_obj = bpy.data.objects.new("__LookDev_Key", key_data)
    bpy.context.collection.objects.link(key_obj)
    key_obj.location = center + Vector((-dist, -dist, dist * 1.2))
    key_obj.rotation_euler = (math.radians(46), 0, math.radians(-36))

    # 2. Fill Light (冷蓝辅光)
    fill_data = bpy.data.lights.new(name="__LookDev_Fill", type='SUN')
    fill_data.energy = 1.2
    fill_data.color = (0.85, 0.92, 1.0)
    fill_data.angle = math.radians(35.0)
    fill_data.use_shadow = False
    fill_obj = bpy.data.objects.new("__LookDev_Fill", fill_data)
    bpy.context.collection.objects.link(fill_obj)
    fill_obj.location = center + Vector((dist, -dist * 0.6, dist * 0.7))
    fill_obj.rotation_euler = (math.radians(60), 0, math.radians(45))

    # 3. Rim Light (背光轮廓高光)
    rim_data = bpy.data.lights.new(name="__LookDev_Rim", type='SUN')
    rim_data.energy = 1.8
    rim_data.color = (1.0, 0.98, 1.0)
    rim_data.angle = math.radians(10.0)
    rim_data.use_shadow = False
    rim_obj = bpy.data.objects.new("__LookDev_Rim", rim_data)
    bpy.context.collection.objects.link(rim_obj)
    rim_obj.location = center + Vector((0, dist, dist))
    rim_obj.rotation_euler = (math.radians(-45), 0, 0)


def stitch_horizontal_images(img_paths, out_path, tile_res):
    """使用 bpy.data.images 将 3 张正方形渲染图横向拼接为 1 张 (3*tile_res) x tile_res 卡片。"""
    loaded = [bpy.data.images.load(p) for p in img_paths]
    total_w = tile_res * len(loaded)
    total_h = tile_res

    canvas = bpy.data.images.new(
        name="__LookDev_Card",
        width=total_w,
        height=total_h,
        alpha=True,
    )

    # 预分配 RGBA 浮点数组 (行优先，从底部到顶部)
    out_pixels = [0.92, 0.93, 0.94, 1.0] * (total_w * total_h)
    tile_buffers = [list(img.pixels[:]) for img in loaded]

    for idx, buf in enumerate(tile_buffers):
        x_offset = idx * tile_res
        for row in range(total_h):
            src_start = row * tile_res * 4
            src_end = src_start + tile_res * 4
            dst_start = (row * total_w + x_offset) * 4
            dst_end = dst_start + tile_res * 4
            out_pixels[dst_start:dst_end] = buf[src_start:src_end]
            # 在分栏边界画一条 2px 浅灰分割线
            if idx > 0:
                sep_idx = (row * total_w + x_offset) * 4
                out_pixels[sep_idx:sep_idx + 8] = [0.76, 0.78, 0.81, 1.0] * 2

    canvas.pixels[:] = out_pixels
    canvas.filepath_raw = out_path
    canvas.file_format = 'PNG'
    canvas.save()

    for img in loaded:
        bpy.data.images.remove(img)
    bpy.data.images.remove(canvas)


def main():
    out_dir, name, res = parse_args()
    if not out_dir:
        blend_dir = os.path.dirname(os.path.abspath(bpy.data.filepath)) if bpy.data.filepath else os.getcwd()
        out_dir = os.path.join(blend_dir, "renders")
    os.makedirs(out_dir, exist_ok=True)

    mesh_objs = [o for o in bpy.data.objects if o.type == 'MESH' and not o.hide_render]
    if not mesh_objs:
        print("❌ [LookDev] 场景中没有可渲染的 MESH 对象！")
        sys.exit(1)

    min_co, max_co = compute_scene_aabb(mesh_objs)
    center = (min_co + max_co) * 0.5
    size = max_co - min_co
    max_span = max(size.x, size.y, size.z, 0.25)

    setup_studio_lighting(center, max_span, min_co.z)

    scene = bpy.context.scene
    for eng in ['BLENDER_EEVEE', 'BLENDER_EEVEE_NEXT', 'CYCLES']:
        try:
            scene.render.engine = eng
            break
        except Exception:
            continue

    scene.render.resolution_x = res
    scene.render.resolution_y = res
    scene.render.film_transparent = False
    scene.render.image_settings.file_format = 'PNG'
    scene.render.image_settings.color_mode = 'RGBA'

    is_character = (size.z > size.x * 1.35)
    cam_data = bpy.data.cameras.new("__LookDev_Cam")
    cam_data.type = 'ORTHO'
    cam_data.ortho_scale = max_span * (1.18 if is_character else 1.32)
    cam_data.clip_start = 0.05
    cam_data.clip_end = max(max_span * 25.0, 200.0)
    cam_obj = bpy.data.objects.new("__LookDev_Cam", cam_data)
    bpy.context.collection.objects.link(cam_obj)
    scene.camera = cam_obj

    dist = max(max_span * 3.0, 3.0)
    views = [
        ("front", Vector((0.0, -1.0, 0.06)).normalized()),
        ("side", Vector((1.0, 0.0, 0.06)).normalized()),
        ("iso34", Vector((-0.55, -0.84, 0.14)).normalized() if is_character else Vector((0.72, -0.72, 0.52)).normalized()),
    ]

    rendered_paths = []
    for tag, direction in views:
        cam_obj.location = center + direction * dist
        look_vec = (center - cam_obj.location).normalized()
        cam_obj.rotation_euler = look_vec.to_track_quat('-Z', 'Y').to_euler()
        out_path = os.path.join(out_dir, f"{name}_{tag}.png")
        scene.render.filepath = out_path
        bpy.ops.render.render(write_still=True)
        rendered_paths.append(out_path)
        print(f"📸 [LookDev] 已渲染 {tag} 视图: {out_path}")

    card_path = os.path.join(out_dir, f"{name}_lookdev_card.png")
    stitch_horizontal_images(rendered_paths, card_path, res)
    print(f"✨ [LookDev] 已合成三合一 LookDev 预览卡: {card_path}")


if __name__ == "__main__":
    main()
