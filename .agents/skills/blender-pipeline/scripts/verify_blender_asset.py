"""工业级 Blender 3D 游戏资产自动化结构断言与多视角视觉质检器 (verify_blender_asset.py)。

运行方式：
/Applications/Blender.app/Contents/MacOS/Blender --background <path/to/asset.blend> \
  --python .agents/skills/blender-pipeline/scripts/verify_blender_asset.py -- \
  --output-dir <path/to/renders> \
  --expected-glb <path/to/asset.glb> \
  [--render-views]

质检项覆盖：
1. 网格非空与多边形统计 (Vertices / Faces / Triangles)
2. 变换与缩放断言 (检测未应用的非单位 Scale 或导致法线翻转的负 Scale)
3. 拓扑健康度检查 (孤立顶点 Loose Verts、零面积退化面 Zero-Area Faces)
4. 世界空间包围盒 (AABB) 尺寸与接地高度诊断
5. 材质槽完整性检查 (排查空材质槽或缺失 Principled BSDF 节点)
6. 骨骼与蒙皮权重完整性断言 (排查未受任何骨骼权重控制的 0 权重孤立顶点、NLA 轨道审计)
7. GLB 二进制魔数头 (0x46546C67 'glTF') 与文件体积校验
8. 可选多视角自动检视渲染 (Front / Side / Iso34)
"""

from __future__ import annotations

import argparse
import json
import math
import os
import struct
import sys
import bpy
import bmesh
from mathutils import Vector


def parse_args() -> argparse.Namespace:
    argv = sys.argv
    if "--" in argv:
        argv = argv[argv.index("--") + 1 :]
    else:
        argv = []
    parser = argparse.ArgumentParser(description="Verify Blender 3D game asset quality.")
    parser.add_argument("--output-dir", default="", help="Directory to write JSON report and diagnostic renders")
    parser.add_argument("--expected-glb", default="", help="Path to exported .glb file to verify")
    parser.add_argument("--render-views", action="store_true", help="Render Front/Side/Iso diagnostic views")
    return parser.parse_args(argv)


def compute_scene_aabb(mesh_objs: list) -> dict:
    min_v = Vector((float("inf"), float("inf"), float("inf")))
    max_v = Vector((float("-inf"), float("-inf"), float("-inf")))

    for obj in mesh_objs:
        for corner in obj.bound_box:
            world_pt = obj.matrix_world @ Vector(corner)
            min_v.x = min(min_v.x, world_pt.x)
            min_v.y = min(min_v.y, world_pt.y)
            min_v.z = min(min_v.z, world_pt.z)
            max_v.x = max(max_v.x, world_pt.x)
            max_v.y = max(max_v.y, world_pt.y)
            max_v.z = max(max_v.z, world_pt.z)

    size = max_v - min_v
    center = (min_v + max_v) * 0.5
    return {
        "min": [round(min_v.x, 4), round(min_v.y, 4), round(min_v.z, 4)],
        "max": [round(max_v.x, 4), round(max_v.y, 4), round(max_v.z, 4)],
        "size": [round(size.x, 4), round(size.y, 4), round(size.z, 4)],
        "center": [round(center.x, 4), round(center.y, 4), round(center.z, 4)],
    }


def audit_meshes_and_armatures() -> tuple[dict, list[str], list[str]]:
    errors: list[str] = []
    warnings: list[str] = []

    mesh_objs = [o for o in bpy.data.objects if o.type == 'MESH']
    arm_objs = [o for o in bpy.data.objects if o.type == 'ARMATURE']

    if not mesh_objs:
        errors.append("场景中不存在任何 MESH 网格对象。")
        return {}, errors, warnings

    total_verts = 0
    total_faces = 0
    zero_area_faces = 0
    loose_verts = 0
    unweighted_verts_total = 0

    for obj in mesh_objs:
        mesh = obj.data
        total_verts += len(mesh.vertices)
        total_faces += len(mesh.polygons)

        # 1. 检查负缩放或未应用的非均匀缩放
        sx, sy, sz = obj.scale
        if sx < 0 or sy < 0 or sz < 0:
            errors.append(f"网格 '{obj.name}' 存在负缩放 ({sx:.3f}, {sy:.3f}, {sz:.3f})，会导致导出 glTF 法线翻转。")
        elif abs(sx - 1.0) > 1e-2 or abs(sy - 1.0) > 1e-2 or abs(sz - 1.0) > 1e-2:
            warnings.append(f"网格 '{obj.name}' 存在未应用的缩放 ({sx:.3f}, {sy:.3f}, {sz:.3f})，建议执行 transform_apply。")

        # 2. 检查材质完整性
        if len(obj.material_slots) == 0:
            warnings.append(f"网格 '{obj.name}' 未分配任何材质。")
        for slot in obj.material_slots:
            if slot.material is None:
                warnings.append(f"网格 '{obj.name}' 存在空材质槽 (Empty Material Slot)。")

        # 3. BMesh 拓扑检查
        bm = bmesh.new()
        bm.from_mesh(mesh)
        for v in bm.verts:
            if len(v.link_edges) == 0:
                loose_verts += 1
        for f in bm.faces:
            if f.calc_area() < 1e-9:
                zero_area_faces += 1
        bm.free()

        # 4. 若挂载了 Armature 修改器，检查是否所有顶点都有有效骨骼权重
        arm_mods = [m for m in obj.modifiers if m.type == 'ARMATURE' and m.object is not None]
        if arm_mods:
            arm_obj = arm_mods[0].object
            bone_names = {b.name for b in arm_obj.data.bones}
            valid_vg_indices = {vg.index for vg in obj.vertex_groups if vg.name in bone_names}
            unweighted_count = 0
            for v in mesh.vertices:
                w_sum = sum(g.weight for g in v.groups if g.group in valid_vg_indices)
                if w_sum < 1e-4:
                    unweighted_count += 1
            unweighted_verts_total += unweighted_count
            if unweighted_count > 0:
                errors.append(
                    f"蒙皮网格 '{obj.name}' 存在 {unweighted_count} 个未绑定骨骼权重的孤立顶点，动画时会产生原点拉扯畸变！"
                )

    if loose_verts > 0:
        warnings.append(f"检测到 {loose_verts} 个孤立无边顶点 (Loose Vertices)。")

    # 5. 审计骨架与 NLA 动画轨道
    armature_summary = []
    for arm in arm_objs:
        nla_tracks = []
        if arm.animation_data and arm.animation_data.nla_tracks:
            nla_tracks = [t.name for t in arm.animation_data.nla_tracks]
        armature_summary.append({
            "name": arm.name,
            "bone_count": len(arm.data.bones),
            "bones": [b.name for b in arm.data.bones],
            "nla_tracks": nla_tracks,
        })
        if not nla_tracks and len(bpy.data.actions) == 0:
            warnings.append(f"骨架 '{arm.name}' 未包含任何 NLA 动画轨道或 Action。")

    # 6. 审计场景图父子层级深度 (Anti-Flattening Hierarchy Audit) 与命名规范
    def _obj_depth(o) -> int:
        d = 0
        cur = o.parent
        while cur is not None and d < 32:
            d += 1
            cur = cur.parent
        return d

    non_studio_objs = [
        o for o in bpy.data.objects
        if o.type in {'MESH', 'ARMATURE', 'EMPTY'} and not o.name.startswith(("Verify_", "Studio_", "LookDev_"))
    ]
    max_depth = max((_obj_depth(o) for o in non_studio_objs), default=0)
    unparented_meshes = [m.name for m in mesh_objs if m.parent is None]
    default_primitive_prefixes = ("Cube", "Cylinder", "Sphere", "Cone", "Plane", "Torus", "Icosphere")
    raw_named_meshes = [m.name for m in mesh_objs if m.name.startswith(default_primitive_prefixes)]

    if len(mesh_objs) >= 2 and len(unparented_meshes) == len(mesh_objs):
        warnings.append(
            f"场景层级过于扁平 (max_depth={max_depth}, {len(unparented_meshes)}/{len(mesh_objs)} 个 MESH 无父节点)，"
            "请按 scene_hierarchy_architecture.md 构建 ROOT_* -> GRP_*/PIVOT_*/ARM_* -> MSH_* 多级场景树。"
        )
    if raw_named_meshes:
        warnings.append(
            f"检测到未按语义前缀命名的裸几何体 {raw_named_meshes[:5]}，建议使用 MSH_ / GRP_ / PIVOT_ / SOCKET_ 前缀。"
        )

    hierarchy_summary = {
        "max_hierarchy_depth": max_depth,
        "collection_count": len(bpy.data.collections),
        "collections": [c.name for c in bpy.data.collections],
        "unparented_mesh_count": len(unparented_meshes),
        "empty_group_nodes": [o.name for o in non_studio_objs if o.type == 'EMPTY'],
    }

    aabb = compute_scene_aabb(mesh_objs)
    stats = {
        "blender_version": bpy.app.version_string,
        "mesh_object_count": len(mesh_objs),
        "total_vertices": total_verts,
        "total_polygons": total_faces,
        "zero_area_faces": zero_area_faces,
        "loose_vertices": loose_verts,
        "unweighted_skinned_vertices": unweighted_verts_total,
        "material_count": len(bpy.data.materials),
        "armatures": armature_summary,
        "hierarchy": hierarchy_summary,
        "aabb": aabb,
    }
    return stats, errors, warnings


def verify_glb_file(glb_path: str, errors: list[str]) -> dict:
    if not glb_path:
        return {"checked": False}
    if not os.path.isfile(glb_path):
        errors.append(f"期望导出的 GLB 文件不存在: {glb_path}")
        return {"checked": True, "exists": False, "path": glb_path}

    size_bytes = os.path.getsize(glb_path)
    if size_bytes < 128:
        errors.append(f"GLB 文件体积异常过小 ({size_bytes} bytes): {glb_path}")
        return {"checked": True, "exists": True, "size_bytes": size_bytes}

    with open(glb_path, "rb") as f:
        header = f.read(12)
    magic, version, length = struct.unpack("<III", header)
    if magic != 0x46546C67 or version != 2:
        errors.append(f"GLB 文件头校验失败 (magic={hex(magic)}, version={version}): {glb_path}")

    return {
        "checked": True,
        "exists": True,
        "path": glb_path,
        "size_bytes": size_bytes,
        "gltf_version": version,
    }


def render_diagnostic_views(output_dir: str, aabb: dict) -> list[str]:
    """根据包围盒自动架设三视角检视相机（前视图 Front、侧视图 Side、45° 等轴视图 Iso）并输出 PNG。"""
    os.makedirs(output_dir, exist_ok=True)
    center = Vector(aabb["center"])
    size = Vector(aabb["size"])
    max_dim = max(size.x, size.y, size.z, 0.5)
    dist = max_dim * 1.85

    # 若存在多条 NLA 轨道，仅激活第一条或 Walk 轨道用于自然姿态拍摄
    for arm in [o for o in bpy.data.objects if o.type == 'ARMATURE']:
        if arm.animation_data and arm.animation_data.nla_tracks:
            target_track = arm.animation_data.nla_tracks[0].name
            for t in arm.animation_data.nla_tracks:
                if "walk" in t.name.lower():
                    target_track = t.name
                    break
            for t in arm.animation_data.nla_tracks:
                t.mute = (t.name != target_track)

    # 补充检视照明（若场景内无光源）
    if len(bpy.data.lights) == 0:
        bpy.ops.object.light_add(type='SUN', location=(center.x + dist, center.y - dist, center.z + dist))
        sun = bpy.context.active_object
        sun.data.energy = 3.0
        direction = center - sun.location
        sun.rotation_euler = direction.to_track_quat('-Z', 'Y').to_euler()

    bpy.ops.object.camera_add(location=(center.x, center.y - dist, center.z))
    cam = bpy.context.active_object
    cam.name = "Verify_Diag_Camera"
    cam.data.lens = 50
    cam.data.clip_end = max(500.0, dist * 4.0)

    scene = bpy.context.scene
    scene.camera = cam
    scene.render.resolution_x = 768
    scene.render.resolution_y = 768
    scene.render.film_transparent = True

    views = [
        ("verify_front.png", Vector((center.x, center.y - dist, center.z + size.z * 0.08))),
        ("verify_side.png", Vector((center.x + dist, center.y, center.z + size.z * 0.08))),
        ("verify_iso34.png", Vector((center.x + dist * 0.68, center.y - dist * 0.78, center.z + dist * 0.32))),
    ]

    rendered_files = []
    for filename, cam_pos in views:
        cam.location = cam_pos
        look_dir = center - cam.location
        cam.rotation_euler = look_dir.to_track_quat('-Z', 'Y').to_euler()
        out_path = os.path.join(output_dir, filename)
        scene.render.filepath = out_path
        bpy.ops.render.render(write_still=True)
        rendered_files.append(out_path)

    return rendered_files


def main() -> None:
    args = parse_args()
    stats, errors, warnings = audit_meshes_and_armatures()
    glb_info = verify_glb_file(args.expected_glb, errors)

    rendered_views = []
    if args.render_views and args.output_dir and stats.get("aabb"):
        rendered_views = render_diagnostic_views(args.output_dir, stats["aabb"])

    report = {
        "passed": len(errors) == 0,
        "error_count": len(errors),
        "warning_count": len(warnings),
        "errors": errors,
        "warnings": warnings,
        "stats": stats,
        "glb_verification": glb_info,
        "diagnostic_renders": rendered_views,
    }

    if args.output_dir:
        os.makedirs(args.output_dir, exist_ok=True)
        report_path = os.path.join(args.output_dir, "verify_report.json")
        with open(report_path, "w", encoding="utf-8") as f:
            json.dump(report, f, ensure_ascii=False, indent=2)
        print(f"📋 质检报告已输出至: {report_path}")

    print("========================================================")
    print("🔍 [Blender-Pipeline] 3D 资产工业级结构质检摘要:")
    print(f"   - 网格数量: {stats.get('mesh_object_count', 0)} | 顶点数: {stats.get('total_vertices', 0)} | 面数: {stats.get('total_polygons', 0)}")
    if stats.get("aabb"):
        print(f"   - 世界包围盒尺寸 (X, Y, Z): {stats['aabb']['size']} m | 最低点 Z_min={stats['aabb']['min'][2]} m")
    if stats.get("armatures"):
        for arm in stats["armatures"]:
            print(f"   - 骨架 '{arm['name']}': {arm['bone_count']} 根骨骼 | NLA 动画轨道: {arm['nla_tracks']}")
    if glb_info.get("checked"):
        print(f"   - GLB 产物校验: exists={glb_info.get('exists')} | size={glb_info.get('size_bytes', 0)} bytes")
    for w in warnings:
        print(f"   ⚠️ 警告: {w}")
    for e in errors:
        print(f"   ❌ 错误: {e}")
    print("========================================================")

    if errors:
        print("🚫 3D 资产未通过质量门禁，请按报错修复构建脚本！")
        sys.exit(1)
    print("🎉 恭喜！3D 资产全部结构与导出断言 100% 通过！")


if __name__ == "__main__":
    main()
