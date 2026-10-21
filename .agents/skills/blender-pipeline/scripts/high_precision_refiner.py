"""工业级高精度角色分件精加工器 (high_precision_refiner.py)。

功能概述：
将 AI 生成或素体剥离出的“软塌粗糙网格”自动化改造为“高面数精致部件”（适用于独立服装层、软甲、皮带、领口、袖口、护肩）：
1. BMesh 拓扑分析：自动识别开口边界边 (Boundary Edges) 与流形结构转折边 (Sharp Edges)，
   注入 Subdivision Crease (`crease_edge`) 与 Bevel Weight (`bevel_weight_edge`)，并仅对内部顶点做平滑去噪（消除橘皮噪点且锁死边界不缩水）。
2. 非破坏性高模修改器栈：
   HP_Weld -> HP_Solidify (NON_MANIFOLD 双面物理厚度) -> HP_MicroBevel (WEIGHT 限权微倒角 + MITER_ARC)
   -> HP_Subsurf (Catmull-Clark 多级细分 + PRESERVE_CORNERS) -> HP_MicroDisplace (可选微观织物/皮革纹理体积置换)
   -> HP_WeightedNormal (加权法线)。
3. 顶点组分件剥离 (`create_procedural_submesh_panel`)：
   从素体指定顶点组 (如 'Armor_Zone' / 'Jacket_Zone') 自动剥离生成贴合身体的独立子网格分件，并自动挂载到工程化层级节点下。

运行方式 A (Blender GUI Scripting)：
在 3D 视口选中目标网格后直接运行本脚本。

运行方式 B (Headless CLI 批处理)：
/Applications/Blender.app/Contents/MacOS/Blender --background <path/to/asset.blend> \
  --python .agents/skills/blender-pipeline/scripts/high_precision_refiner.py -- \
  --target MSH_Char_Jacket --extract-vgroup Armor_Zone --displace-strength 0.0005 --save
"""

from __future__ import annotations

import argparse
import math
import sys
import bpy
import bmesh


# ==============================================================================
# 高精度角色部件精加工默认参数配置 (适用于服装、软甲、皮带、袖口等独立子网格)
# ==============================================================================
REFINE_CONFIG: dict = {
    "sharp_angle_deg": 35.0,       # 自动判定为结构硬边的角度阈值 (度)
    "boundary_crease": 0.85,       # 服装开口边缘的折痕硬度 (0~1，防止细分后领口/袖口缩水变圆)
    "sharp_edge_crease": 0.75,     # 结构转折边的折痕硬度
    "interior_smooth_factor": 0.35,# 内部非边界顶点去噪平滑强度 (消除 AI 网格表面橘皮感)

    "add_thickness": True,         # 是否为单层网格自动增加真实物理厚度
    "thickness_val": 0.004,        # 厚度值 (米，0.004 = 4毫米厚度的精致衣料/皮革)

    "bevel_width": 0.0012,         # 边缘微倒角宽度 (制造高光切面，消除塑料感)
    "bevel_segments": 3,           # 倒角细分段数

    "subdiv_levels_viewport": 2,   # 视口表面细分级别 (面数乘以 16 倍)
    "subdiv_levels_render": 3,     # 渲染表面细分级别 (面数乘以 64 倍)

    "add_micro_displace": False,   # 是否追加程序化微观纹理体积置换 (织物经纬/皮革颗粒)
    "displace_strength": 0.0005,   # 微观置换强度 (米，0.5毫米级物理起伏)
    "displace_noise_scale": 0.015, # 程序化纹理采样尺寸
    "displace_vgroup": "",         # 仅对特定顶点组生效 (留空则作用于全分件)
}


def ensure_object_mode() -> None:
    if bpy.context.active_object and bpy.context.active_object.mode != 'OBJECT':
        bpy.ops.object.mode_set(mode='OBJECT')


def _get_or_create_edge_float_layer(bm: bmesh.types.BMesh, attr_name: str, legacy_layer_attr: str):
    """兼容 Blender 4.x/5.x 泛型属性层 (`crease_edge` / `bevel_weight_edge`) 与 3.x 旧版层。"""
    layer = bm.edges.layers.float.get(attr_name)
    if layer is not None:
        return layer
    if hasattr(bm.edges.layers, legacy_layer_attr):
        legacy_collection = getattr(bm.edges.layers, legacy_layer_attr)
        return legacy_collection.verify()
    return bm.edges.layers.float.new(attr_name)


def inject_precision_creases_and_seams(obj: bpy.types.Object, config: dict | None = None) -> tuple[int, int]:
    """
    核心步骤 1: 使用 bmesh 分析几何拓扑，自动为服装/护甲边界与结构折角注入 Crease (折痕) 与 Bevel Weight。
    解决 AI 网格细分后边缘软塌、糊成一团的痛点，并平滑内部顶点消除橘皮噪点。
    """
    cfg = {**REFINE_CONFIG, **(config or {})}
    mesh = obj.data
    bm = bmesh.new()
    bm.from_mesh(mesh)

    crease_layer = _get_or_create_edge_float_layer(bm, "crease_edge", "crease")
    bevel_layer = _get_or_create_edge_float_layer(bm, "bevel_weight_edge", "bevel_weight")

    angle_rad = math.radians(cfg["sharp_angle_deg"])
    boundary_count = 0
    sharp_count = 0

    for edge in bm.edges:
        # 1. 检测开口边界边 (如领口、袖口、裙摆边缘、护甲外沿)
        if edge.is_boundary:
            edge[crease_layer] = cfg["boundary_crease"]
            edge[bevel_layer] = 1.0
            edge.smooth = False
            boundary_count += 1

        # 2. 检测流形结构转折边 (如衣褶棱线、机甲折面)
        elif edge.is_manifold:
            angle = edge.calc_face_angle(0.0)
            if angle >= angle_rad:
                edge[crease_layer] = cfg["sharp_edge_crease"]
                edge[bevel_layer] = 0.8
                edge.smooth = False
                sharp_count += 1
            else:
                edge.smooth = True

    # 平滑内部顶点以消除 AI 网格表面的细碎橘皮噪点，但绝对锁死边界顶点不位移！
    interior_verts = [v for v in bm.verts if not v.is_boundary]
    if interior_verts and cfg.get("interior_smooth_factor", 0.0) > 0.0:
        bmesh.ops.smooth_vert(
            bm,
            verts=interior_verts,
            factor=cfg["interior_smooth_factor"],
            use_axis_x=True,
            use_axis_y=True,
            use_axis_z=True,
        )

    for face in bm.faces:
        face.smooth = True

    bm.to_mesh(mesh)
    bm.free()
    mesh.update()
    print(f"[拓扑锐化] '{obj.name}': 已锁定 {boundary_count} 条边界边与 {sharp_count} 条结构硬边。")
    return boundary_count, sharp_count


def build_high_poly_modifier_stack(obj: bpy.types.Object, config: dict | None = None) -> None:
    """
    核心步骤 2: 构建非破坏性的工业级高模修改器栈
    (HP_Weld -> HP_Solidify 抽壳 -> HP_MicroBevel 微倒角 -> HP_Subsurf 多级细分
     -> [可选] HP_MicroDisplace 微观纹理体积置换 -> HP_WeightedNormal)
    """
    cfg = {**REFINE_CONFIG, **(config or {})}

    # 清空可能冲突的旧同名修改器
    for mod_name in [
        "HP_Weld",
        "HP_Solidify",
        "HP_MicroBevel",
        "HP_Subsurf",
        "HP_MicroDisplace",
        "HP_WeightedNormal",
    ]:
        if mod_name in obj.modifiers:
            obj.modifiers.remove(obj.modifiers[mod_name])

    # 1. Weld 修改器：消除极近废点
    weld = obj.modifiers.new(name="HP_Weld", type='WELD')
    weld.merge_threshold = 0.0001

    # 2. Solidify (实体化修改器)：赋予精致的双面厚度与高质量边缘法线
    if cfg["add_thickness"]:
        solid = obj.modifiers.new(name="HP_Solidify", type='SOLIDIFY')
        solid.solidify_mode = 'NON_MANIFOLD'  # 支持复杂非流形衣料结构
        solid.thickness = cfg["thickness_val"]
        solid.offset = 0.0                    # 居中加厚
        solid.use_rim = True                  # 自动封口边缘
        solid.bevel_convex = 0.5              # 边缘自动传递倒角权重

    # 3. Bevel (微倒角修改器)：在所有结构硬边和厚度封口处切出细腻的受光高光面
    bevel = obj.modifiers.new(name="HP_MicroBevel", type='BEVEL')
    bevel.limit_method = 'WEIGHT'             # 仅对前面 bmesh 标记的边界与硬边倒角
    bevel.width = cfg["bevel_width"]
    bevel.segments = cfg["bevel_segments"]
    bevel.profile = 0.7                       # 偏硬朗的椭圆截面
    bevel.miter_outer = 'MITER_ARC'           # 弧形外斜接，彻底杜绝拐角网格交叉破面
    bevel.use_clamp_overlap = True            # 开启防重叠保护

    # 4. Subdivision Surface (Catmull-Clark 表面细分)：将网格推向数十万面的极致丝滑度
    subsurf = obj.modifiers.new(name="HP_Subsurf", type='SUBSURF')
    subsurf.subdivision_type = 'CATMULL_CLARK'
    subsurf.levels = cfg["subdiv_levels_viewport"]
    subsurf.render_levels = cfg["subdiv_levels_render"]
    subsurf.use_creases = True                # 启用 bmesh 注入的折痕权重
    subsurf.boundary_smooth = 'PRESERVE_CORNERS'

    # 5. [可选] Displace (微观纹理体积置换)：在数十万顶点上雕刻布料经纬或皮革颗粒
    if cfg.get("add_micro_displace") and abs(cfg.get("displace_strength", 0.0)) > 1e-6:
        tex_name = f"Tex_MicroGrain_{obj.name}"
        grain_tex = bpy.data.textures.get(tex_name) or bpy.data.textures.new(name=tex_name, type='VORONOI')
        if hasattr(grain_tex, "noise_scale"):
            grain_tex.noise_scale = cfg.get("displace_noise_scale", 0.015)
        disp = obj.modifiers.new(name="HP_MicroDisplace", type='DISPLACE')
        disp.texture = grain_tex
        disp.strength = cfg["displace_strength"]
        disp.mid_level = 0.5
        if cfg.get("displace_vgroup") and cfg["displace_vgroup"] in obj.vertex_groups:
            disp.vertex_group = cfg["displace_vgroup"]

    # 6. Weighted Normal (加权法线)：让大平面绝对平整，高光全部集中到微倒角边缘
    wn = obj.modifiers.new(name="HP_WeightedNormal", type='WEIGHTED_NORMAL')
    wn.mode = 'FACE_AREA_WITH_ANGLE'
    wn.weight = 50
    wn.keep_sharp = True


def create_procedural_submesh_panel(
    base_obj: bpy.types.Object,
    vertex_group_name: str,
    panel_name: str = "MSH_Char_SubPlate",
    parent_grp: bpy.types.Object | None = None,
    target_col: bpy.types.Collection | None = None,
    surface_offset: float = 0.002,
    config: dict | None = None,
) -> bpy.types.Object | None:
    """
    进阶功能: 从角色素体的指定顶点组 (Vertex Group) 自动剥离并生成一块完全贴合身体的高精独立护甲/服装分件，
    并自动挂载到工程化场景树父节点 (parent_grp / base_obj.parent) 下。
    """
    vg = base_obj.vertex_groups.get(vertex_group_name)
    if not vg:
        return None

    vg_idx = vg.index
    bm = bmesh.new()
    bm.from_mesh(base_obj.data)
    deform_layer = bm.verts.layers.deform.active

    if not deform_layer:
        bm.free()
        return None

    verts_to_keep = {v for v in bm.verts if vg_idx in v[deform_layer] and v[deform_layer][vg_idx] > 0.5}
    if not verts_to_keep:
        bm.free()
        return None

    verts_to_del = [v for v in bm.verts if v not in verts_to_keep]
    bmesh.ops.delete(bm, geom=verts_to_del, context='VERTS')

    new_mesh = bpy.data.meshes.new(name=f"{panel_name}_Mesh")
    bm.to_mesh(new_mesh)
    bm.free()

    panel_obj = bpy.data.objects.new(name=panel_name, object_data=new_mesh)
    panel_obj.matrix_world = base_obj.matrix_world.copy()

    col = target_col or (base_obj.users_collection[0] if base_obj.users_collection else bpy.context.collection)
    col.objects.link(panel_obj)

    # 保持工程化树状层级：挂载到指定的 GRP_* 分组或与 base_obj 同级的父节点下
    effective_parent = parent_grp or base_obj.parent
    if effective_parent is not None:
        bpy.context.view_layer.update()
        world_mat = panel_obj.matrix_world.copy()
        panel_obj.parent = effective_parent
        panel_obj.matrix_parent_inverse = effective_parent.matrix_world.inverted()
        panel_obj.matrix_world = world_mat

    # 先挂载 Shrinkwrap 保证与角色身体 100% 严丝合缝，再套用整套高精度修改器栈
    sw = panel_obj.modifiers.new(name="Snap_To_Body", type='SHRINKWRAP')
    sw.target = base_obj
    sw.wrap_method = 'NEAREST_SURFACEPOINT'
    sw.offset = surface_offset

    inject_precision_creases_and_seams(panel_obj, config)
    build_high_poly_modifier_stack(panel_obj, config)
    return panel_obj


def parse_cli_args() -> argparse.Namespace:
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser(description="High-precision character sub-mesh refiner.")
    parser.add_argument("--target", default="", help="Target mesh object name (defaults to active_object)")
    parser.add_argument("--extract-vgroup", default="Armor_Zone", help="Vertex group name to peel off as sub-panel")
    parser.add_argument("--thickness", type=float, default=REFINE_CONFIG["thickness_val"], help="Solidify thickness (m)")
    parser.add_argument("--bevel-width", type=float, default=REFINE_CONFIG["bevel_width"], help="Micro-bevel width (m)")
    parser.add_argument("--displace-strength", type=float, default=0.0, help="Micro-displacement strength (m)")
    parser.add_argument("--save", action="store_true", help="Save main blend file after refinement")
    return parser.parse_args(argv)


def run_high_precision_refiner() -> None:
    args = parse_cli_args()
    obj = bpy.data.objects.get(args.target) if args.target else bpy.context.active_object
    if not obj or obj.type != 'MESH':
        raise RuntimeError("请指定有效的 --target <MeshName> 或在 3D 视口中选中目标网格！")

    ensure_object_mode()
    bpy.ops.object.select_all(action='DESELECT')
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)

    cfg = dict(REFINE_CONFIG)
    cfg["thickness_val"] = args.thickness
    cfg["bevel_width"] = args.bevel_width
    if args.displace_strength > 0.0:
        cfg["add_micro_displace"] = True
        cfg["displace_strength"] = args.displace_strength

    # 1. 自动分析拓扑并注入边界/折角硬化权重
    inject_precision_creases_and_seams(obj, cfg)

    # 2. 挂载工业级高模修改器栈
    build_high_poly_modifier_stack(obj, cfg)

    # 3. 若存在指定顶点组 (如 'Armor_Zone')，自动剥离生成独立高精护甲/服装分件
    if args.extract_vgroup and args.extract_vgroup in obj.vertex_groups:
        panel = create_procedural_submesh_panel(
            obj,
            args.extract_vgroup,
            panel_name=f"MSH_{obj.name}_{args.extract_vgroup}_Plate",
            config=cfg,
        )
        if panel:
            print(f"✨ 已从顶点组 '{args.extract_vgroup}' 自动剥离并生成高精独立分件: {panel.name}")

    if args.save and bpy.data.filepath:
        bpy.ops.wm.save_mainfile()

    print(f"✅ [{obj.name}] 高精度高面数改造完成！")


if __name__ == "__main__":
    run_high_precision_refiner()
