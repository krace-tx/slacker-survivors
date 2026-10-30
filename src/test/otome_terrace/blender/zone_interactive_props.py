# -*- coding: utf-8 -*-
"""Stage Module 2: Three Outdoor Interactive Zones (Blossom Bench, Vintage Coffee Cart & Parasol, Lakeside Fountain & Hydrangeas) + Vintage Lampposts & Festoon String Lights."""

from __future__ import annotations

import math
import bpy
import bmesh
from mathutils import Vector

from blender_core import (
    _finalize_mesh_object,
    create_hierarchy_node,
    make_box,
    make_capsule_tube,
    make_curved_leaf,
    make_cylinder,
    make_soft_cushion,
    make_torus_ring,
)


def _make_sphere(
    name: str,
    radius: float,
    loc: tuple[float, float, float],
    mat: bpy.types.Material,
    parent: bpy.types.Object,
    col: bpy.types.Collection,
    scale_xyz: tuple[float, float, float] = (1.0, 1.0, 1.0),
    u_segs: int = 20,
    v_segs: int = 12,
) -> bpy.types.Object:
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=u_segs, v_segments=v_segs, radius=radius)
    if scale_xyz != (1.0, 1.0, 1.0):
        bmesh.ops.scale(bm, vec=Vector(scale_xyz), verts=bm.verts)
    return _finalize_mesh_object(name, bm, loc, (0.0, 0.0, 0.0), mat, parent, col)


def _make_blossom_cloud(
    name: str,
    radii: tuple[float, float, float],
    loc: tuple[float, float, float],
    seed: int,
    mat: bpy.types.Material,
    parent: bpy.types.Object,
    col: bpy.types.Collection,
) -> bpy.types.Object:
    """Fluffy organic multi-lobed anime cherry blossom cloud cluster (zero boxy cube seams!)."""
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=3, radius=1.0)
    rx, ry, rz = radii
    for v in bm.verts:
        nx, ny, nz = v.co.x, v.co.y, v.co.z
        # Multi-frequency scalloped botanical billows
        billow = (
            1.0
            + 0.16 * math.sin(nx * 4.2 + seed * 1.3) * math.cos(ny * 4.1 - seed * 0.7)
            + 0.10 * math.cos((nx + ny) * 5.8 + nz * 4.6)
        )
        v.co = Vector((nx * rx * billow, ny * ry * billow, nz * rz * billow))
    return _finalize_mesh_object(name, bm, loc, (0.0, 0.0, seed * 23.0), mat, parent, col, subsurf_levels=1)


def _make_parasol_canopy(
    name: str,
    center: tuple[float, float, float],
    radius: float,
    dome_height: float,
    mat_even: bpy.types.Material,
    mat_odd: bpy.types.Material,
    parent: bpy.types.Object,
    col: bpy.types.Collection,
) -> list[bpy.types.Object]:
    """Build 8-wedge alternating striped cream & latte-taupe sun parasol canopy with valance flaps."""
    cx, cy, cz = center
    objs: list[bpy.types.Object] = []
    segs = 8
    for i in range(segs):
        a0 = 2.0 * math.pi * i / segs
        a1 = 2.0 * math.pi * (i + 1) / segs
        am = (a0 + a1) * 0.5
        mat = mat_even if (i % 2 == 0) else mat_odd

        bm = bmesh.new()
        v_apex_t = bm.verts.new((0.0, 0.0, dome_height + 0.015))
        v_apex_b = bm.verts.new((0.0, 0.0, dome_height - 0.015))

        r_mid = radius * 0.54
        z_mid = dome_height * 0.56
        v_m0_t = bm.verts.new((math.cos(a0) * r_mid, math.sin(a0) * r_mid, z_mid + 0.014))
        v_m1_t = bm.verts.new((math.cos(a1) * r_mid, math.sin(a1) * r_mid, z_mid + 0.014))
        v_m0_b = bm.verts.new((math.cos(a0) * r_mid, math.sin(a0) * r_mid, z_mid - 0.014))
        v_m1_b = bm.verts.new((math.cos(a1) * r_mid, math.sin(a1) * r_mid, z_mid - 0.014))

        v_e0_t = bm.verts.new((math.cos(a0) * radius, math.sin(a0) * radius, 0.012))
        v_em_t = bm.verts.new((math.cos(am) * (radius * 1.02), math.sin(am) * (radius * 1.02), 0.024))
        v_e1_t = bm.verts.new((math.cos(a1) * radius, math.sin(a1) * radius, 0.012))

        v_e0_b = bm.verts.new((math.cos(a0) * radius, math.sin(a0) * radius, -0.012))
        v_em_b = bm.verts.new((math.cos(am) * (radius * 1.02), math.sin(am) * (radius * 1.02), 0.0))
        v_e1_b = bm.verts.new((math.cos(a1) * radius, math.sin(a1) * radius, -0.012))

        # Hanging valance flap
        v_f0 = bm.verts.new((math.cos(a0) * radius, math.sin(a0) * radius, -0.13))
        v_fm = bm.verts.new((math.cos(am) * (radius * 1.02), math.sin(am) * (radius * 1.02), -0.15))
        v_f1 = bm.verts.new((math.cos(a1) * radius, math.sin(a1) * radius, -0.13))

        bm.faces.new((v_apex_t, v_m0_t, v_m1_t))
        bm.faces.new((v_m0_t, v_e0_t, v_em_t, v_m1_t))
        bm.faces.new((v_m1_t, v_em_t, v_e1_t))

        bm.faces.new((v_apex_b, v_m1_b, v_m0_b))
        bm.faces.new((v_m1_b, v_em_b, v_e0_b, v_m0_b))
        bm.faces.new((v_e1_b, v_em_b, v_m1_b))

        # Valance double-sided skirt
        bm.faces.new((v_e0_t, v_f0, v_fm, v_em_t))
        bm.faces.new((v_em_t, v_fm, v_f1, v_e1_t))
        bm.faces.new((v_em_b, v_fm, v_f0, v_e0_b))
        bm.faces.new((v_e1_b, v_f1, v_fm, v_em_b))

        objs.append(
            _finalize_mesh_object(f"{name}_Wedge_{i:02d}", bm, (cx, cy, cz), (0.0, 0.0, 0.0), mat, parent, col)
        )
    return objs


def _build_zone_blossom_bench(
    parent_grp: bpy.types.Object,
    export_col: bpy.types.Collection,
    mats: dict[str, bpy.types.Material],
) -> bpy.types.Object:
    """Zone 1: Blooming Cherry/Apricot Blossom Tree + Wrought-Iron & Oak Park Bench + Fallen Petals."""
    zone = create_hierarchy_node("ZONE_01_Blossom_Bench", parent=parent_grp, collection=export_col)

    # 1. Giant Blooming Cherry Blossom Tree at (-3.85, 1.48, 0.0)
    tx, ty = -3.85, 1.48
    grp_tree = create_hierarchy_node("CLUSTER_Cherry_BlossomTree", parent=zone, collection=export_col, location=(tx, ty, 0.0))

    # Sculpted root flares & tapered gnarled trunk
    for ri in range(5):
        ra = ri * (2.0 * math.pi / 5.0) + 0.25
        make_capsule_tube(
            f"MSH_CherryTree_Root_{ri:02d}",
            (tx + math.cos(ra) * 0.14, ty + math.sin(ra) * 0.14, 0.36),
            (tx + math.cos(ra) * 0.56, ty + math.sin(ra) * 0.56, -0.02),
            0.12,
            0.055,
            mats["tree_bark"],
            grp_tree,
            export_col,
        )
    make_capsule_tube("MSH_CherryTree_LowerTrunk", (tx, ty, -0.02), (tx + 0.08, ty - 0.06, 1.38), 0.29, 0.21, mats["tree_bark"], grp_tree, export_col)
    make_capsule_tube("MSH_CherryTree_MidTrunk", (tx + 0.08, ty - 0.06, 1.32), (tx + 0.22, ty - 0.14, 2.38), 0.21, 0.14, mats["tree_bark"], grp_tree, export_col)

    branches = [
        ((tx + 0.18, ty - 0.12, 2.15), (tx + 1.45, ty - 0.72, 3.05), 0.12, 0.055),
        ((tx + 0.20, ty - 0.10, 2.28), (tx + 0.92, ty + 0.88, 3.35), 0.11, 0.050),
        ((tx + 0.14, ty - 0.08, 2.18), (tx - 1.05, ty - 0.85, 3.12), 0.12, 0.055),
        ((tx + 0.15, ty - 0.05, 2.25), (tx - 1.18, ty + 0.78, 3.28), 0.11, 0.050),
        ((tx + 0.22, ty - 0.14, 2.34), (tx + 0.35, ty - 0.18, 3.72), 0.11, 0.048),
        ((tx + 0.88, ty - 0.45, 2.72), (tx + 1.92, ty - 0.98, 2.96), 0.065, 0.032),
    ]
    for bi, (b0, b1, r0, r1) in enumerate(branches):
        make_capsule_tube(f"MSH_CherryTree_Branch_{bi:02d}", b0, b1, r0, r1, mats["tree_bark"], grp_tree, export_col)

    # Fluffy Layered Organic Blossom Cloud Clusters forming a romantic canopy overhanging the bench!
    canopy_puffs = [
        (0.22, -0.14, 3.85, 0.92, 0.86, 0.64, "blossom_ivory"),
        (1.08, -0.62, 3.28, 0.84, 0.78, 0.56, "blossom_pink"),
        (1.78, -0.92, 3.00, 0.70, 0.66, 0.48, "blossom_ivory"),
        (0.84, 0.72, 3.44, 0.82, 0.78, 0.56, "blossom_pink"),
        (-0.86, -0.76, 3.24, 0.84, 0.76, 0.56, "blossom_pink"),
        (-1.08, 0.66, 3.36, 0.86, 0.80, 0.58, "blossom_ivory"),
        (-0.14, -1.02, 3.40, 0.76, 0.70, 0.52, "blossom_deep"),
        (0.54, -1.18, 3.12, 0.68, 0.64, 0.48, "blossom_pink"),
        (-0.20, 0.98, 3.52, 0.78, 0.72, 0.54, "blossom_pink"),
        (1.38, 0.14, 3.34, 0.74, 0.70, 0.50, "blossom_deep"),
        (-1.42, -0.10, 3.18, 0.74, 0.70, 0.50, "blossom_pink"),
        (0.28, 0.10, 4.18, 0.76, 0.72, 0.50, "blossom_ivory"),
        (0.68, -0.25, 3.62, 0.72, 0.68, 0.48, "blossom_ivory"),
        (-0.55, 0.08, 3.68, 0.76, 0.72, 0.52, "blossom_pink"),
    ]
    for ci, (ox, oy, oz, rx, ry, rz, mkey) in enumerate(canopy_puffs):
        _make_blossom_cloud(
            f"MSH_CherryTree_Canopy_{ci:02d}",
            (rx, ry, rz),
            (tx + ox, ty + oy, oz),
            ci + 1,
            mats[mkey],
            grp_tree,
            export_col,
        )
    # Outer accent blossom florets dotting the lower canopy facing the camera
    for fi in range(22):
        fa = fi * 0.54 - 1.2
        fr = 0.85 + (fi % 4) * 0.34
        fx_b = tx + 0.25 + math.cos(fa) * fr
        fy_b = ty - 0.22 + math.sin(fa) * (fr * 0.82)
        fz_b = 2.72 + (fi % 5) * 0.22
        _make_sphere(
            f"MSH_CherryTree_Floret_{fi:02d}",
            0.13 + (fi % 3) * 0.025,
            (fx_b, fy_b, fz_b),
            mats["blossom_ivory"] if fi % 2 == 0 else mats["blossom_deep"],
            grp_tree,
            export_col,
            scale_xyz=(1.0, 1.0, 0.78),
            u_segs=14,
            v_segs=10,
        )

    # 2. Ornate Wrought-Iron & Honey-Oak Park Bench at (-2.72, 0.68, 0.0), yaw = -28 deg facing walkway
    bx, by = -2.72, 0.68
    byaw = -28.0
    rad = math.radians(byaw)
    ca, sa = math.cos(rad), math.sin(rad)

    def bench_pt(lx: float, ly: float, lz: float) -> tuple[float, float, float]:
        return (bx + lx * ca - ly * sa, by + lx * sa + ly * ca, lz)

    grp_bench = create_hierarchy_node("CLUSTER_Park_Bench", parent=zone, collection=export_col, location=(bx, by, 0.0))

    # Left & Right cast-iron leg frames & curved armrests
    for side_x, tag in ((-0.74, "L"), (0.74, "R")):
        make_capsule_tube(f"MSH_Bench_FrontLeg_{tag}", bench_pt(side_x, -0.24, 0.01), bench_pt(side_x, -0.21, 0.44), 0.026, 0.022, mats["iron_forest"], grp_bench, export_col)
        make_capsule_tube(f"MSH_Bench_BackLeg_{tag}", bench_pt(side_x, 0.24, 0.01), bench_pt(side_x, 0.30, 0.88), 0.026, 0.022, mats["iron_forest"], grp_bench, export_col)
        make_capsule_tube(f"MSH_Bench_SeatSupport_{tag}", bench_pt(side_x, -0.24, 0.42), bench_pt(side_x, 0.24, 0.41), 0.022, 0.022, mats["iron_forest"], grp_bench, export_col)
        make_capsule_tube(f"MSH_Bench_ArmRest_{tag}", bench_pt(side_x, -0.23, 0.61), bench_pt(side_x, 0.26, 0.62), 0.022, 0.020, mats["iron_forest"], grp_bench, export_col)
        make_capsule_tube(f"MSH_Bench_ArmPost_{tag}", bench_pt(side_x, -0.21, 0.43), bench_pt(side_x, -0.23, 0.61), 0.018, 0.018, mats["iron_forest"], grp_bench, export_col)
        make_torus_ring(f"MSH_Bench_Scroll_{tag}", 0.075, 0.013, bench_pt(side_x, 0.0, 0.51), mats["brass"], grp_bench, export_col, major_segs=24, minor_segs=8, rot_deg=(0.0, 90.0, byaw))

    # 5 Honey-Oak Seat Slats + 3 Curved Backrest Slats + Brass Crest Medallion
    for si in range(5):
        ly = -0.20 + si * 0.095
        make_box(f"MSH_Bench_SeatSlat_{si:02d}", (1.64, 0.072, 0.028), bench_pt(0.0, ly, 0.445), mats["cedar_plank_b"], grp_bench, export_col, bevel=0.006, rot_deg=(0.0, 0.0, byaw))
    for bi_s in range(3):
        lz = 0.58 + bi_s * 0.115
        ly = 0.255 + bi_s * 0.022
        make_box(f"MSH_Bench_BackSlat_{bi_s:02d}", (1.64, 0.028, 0.082), bench_pt(0.0, ly, lz), mats["cedar_plank_a"], grp_bench, export_col, bevel=0.006, rot_deg=(-11.0, 0.0, byaw))
    make_torus_ring("MSH_Bench_CrownCrest", 0.11, 0.014, bench_pt(0.0, 0.30, 0.90), mats["brass"], grp_bench, export_col, major_segs=28, minor_segs=8, rot_deg=(79.0, 0.0, byaw))

    # Open Poetry Book & Soft Folded Throw on Bench
    make_soft_cushion("MSH_Bench_FoldedScarf", (0.36, 0.34, 0.055), bench_pt(-0.42, 0.02, 0.48), mats["cart_cream"], grp_bench, export_col, rot_deg=(0.0, 0.0, byaw + 14.0), puff=0.18, subsurf=1)
    make_box("MSH_Bench_PoetryBookL", (0.16, 0.22, 0.022), bench_pt(0.32, -0.02, 0.472), mats["cart_cream"], grp_bench, export_col, bevel=0.004, rot_deg=(0.0, -8.0, byaw - 16.0))
    make_box("MSH_Bench_PoetryBookR", (0.16, 0.22, 0.022), bench_pt(0.46, 0.02, 0.472), mats["blossom_ivory"], grp_bench, export_col, bevel=0.004, rot_deg=(0.0, 8.0, byaw - 16.0))

    # Scattered fallen pink cherry petals around tree & bench
    for pi in range(18):
        pa = pi * 2.18
        pr = 0.55 + (pi % 5) * 0.34
        px = bx - 0.35 + math.cos(pa) * pr
        py = by + 0.15 + math.sin(pa) * (pr * 0.78)
        make_soft_cushion(
            f"MSH_Fallen_Petal_{pi:02d}",
            (0.085, 0.058, 0.014),
            (px, py, 0.016),
            mats["blossom_pink"] if pi % 2 == 0 else mats["blossom_ivory"],
            zone,
            export_col,
            rot_deg=(0.0, 0.0, pi * 37.0),
            puff=0.20,
            subsurf=1,
        )

    return zone


def _build_zone_coffee_cart(
    parent_grp: bpy.types.Object,
    export_col: bpy.types.Collection,
    mats: dict[str, bpy.types.Material],
) -> bpy.types.Object:
    """Zone 2: Vintage Open-Air Wheeled Coffee Cart + Striped Sun Parasol + Lakeside Bistro Table."""
    deck_z = 0.16
    zone = create_hierarchy_node("ZONE_02_OpenAir_CoffeeCart", parent=parent_grp, collection=export_col, location=(0.65, 2.95, deck_z))

    # 1. Vintage Cream & Walnut Wheeled Coffee Cart at (0.12, 3.05, deck_z)
    cx, cy = 0.12, 3.05
    grp_cart = create_hierarchy_node("CLUSTER_Vintage_CoffeeCart", parent=zone, collection=export_col, location=(cx, cy, deck_z))

    # Body cabinet (width 1.48m, depth 0.72m, counter height above deck 0.90m)
    make_box("MSH_Cart_CabinetBody", (1.42, 0.68, 0.66), (cx, cy, deck_z + 0.53), mats["cart_cream"], grp_cart, export_col, bevel=0.014)
    for pi_idx, px_off in enumerate((-0.42, 0.42)):
        make_box(f"MSH_Cart_FrontPanel_{pi_idx}", (0.52, 0.022, 0.46), (cx + px_off, cy - 0.345, deck_z + 0.53), mats["parasol_taupe"], grp_cart, export_col, bevel=0.006)
        make_box(f"MSH_Cart_InnerInset_{pi_idx}", (0.44, 0.018, 0.38), (cx + px_off, cy - 0.352, deck_z + 0.53), mats["cart_cream"], grp_cart, export_col, bevel=0.005)
    make_box("MSH_Cart_OakCounter", (1.54, 0.78, 0.052), (cx, cy, deck_z + 0.885), mats["cedar_plank_b"], grp_cart, export_col, bevel=0.012)
    # Brass push bar handle on right side
    make_capsule_tube("MSH_Cart_PushBar", (cx + 0.84, cy - 0.26, deck_z + 0.86), (cx + 0.84, cy + 0.26, deck_z + 0.86), 0.016, 0.016, mats["brass"], grp_cart, export_col)
    for hy in (-0.22, 0.22):
        make_capsule_tube(f"MSH_Cart_HandleArm_{hy:+.2f}", (cx + 0.72, cy + hy, deck_z + 0.84), (cx + 0.84, cy + hy, deck_z + 0.86), 0.014, 0.014, mats["brass"], grp_cart, export_col)

    # Two Large Spoked Vintage Carriage Wheels (with PIVOT_* nodes!) + Rear Support Legs
    for wy, side_tag in ((cy - 0.38, "Front"), (cy + 0.38, "Back")):
        wx = cx - 0.36
        wz = deck_z + 0.27
        piv = create_hierarchy_node(f"PIVOT_Cart_Wheel_{side_tag}", parent=grp_cart, collection=export_col, location=(wx, wy, wz), display_type="ARROWS", display_size=0.12)
        make_torus_ring(f"MSH_Cart_WheelRim_{side_tag}", 0.255, 0.022, (wx, wy, wz), mats["wood_walnut"], piv, export_col, major_segs=32, minor_segs=10, rot_deg=(90.0, 0.0, 0.0))
        make_torus_ring(f"MSH_Cart_WheelBrass_{side_tag}", 0.270, 0.009, (wx, wy, wz), mats["brass"], piv, export_col, major_segs=32, minor_segs=8, rot_deg=(90.0, 0.0, 0.0))
        make_cylinder(f"MSH_Cart_WheelHub_{side_tag}", 0.048, 0.06, (wx, wy, wz), mats["brass"], piv, export_col, segs=18, rot_deg=(90.0, 0.0, 0.0))
        for spk in range(8):
            sa = spk * (math.pi / 4.0)
            make_capsule_tube(
                f"MSH_Cart_Spoke_{side_tag}_{spk}",
                (wx, wy, wz),
                (wx + math.cos(sa) * 0.24, wy, wz + math.sin(sa) * 0.24),
                0.010,
                0.009,
                mats["wood_walnut"],
                piv,
                export_col,
            )
    for ry_leg in (-0.30, 0.30):
        make_cylinder(f"MSH_Cart_SupportLeg_{ry_leg:+.2f}", 0.024, 0.22, (cx + 0.52, cy + ry_leg, deck_z + 0.11), mats["wood_walnut"], grp_cart, export_col, r_top=0.032)

    # Countertop Props: Espresso Machine, Glass Pastry Case + Croissants, Pour-Over Kettle & Cups
    ct_z = deck_z + 0.91
    make_box("MSH_Cart_EspressoBody", (0.42, 0.32, 0.34), (cx - 0.42, cy + 0.06, ct_z + 0.17), mats["cart_cream"], grp_cart, export_col, bevel=0.016)
    make_box("MSH_Cart_EspressoTop", (0.44, 0.34, 0.032), (cx - 0.42, cy + 0.06, ct_z + 0.35), mats["brass"], grp_cart, export_col, bevel=0.008)
    make_cylinder("MSH_Cart_GroupHead", 0.042, 0.05, (cx - 0.42, cy - 0.10, ct_z + 0.20), mats["brass"], grp_cart, export_col)

    # Glass Pastry Display Case with 2 Golden Croissants
    make_box("MSH_Cart_PastryBase", (0.38, 0.28, 0.03), (cx + 0.14, cy - 0.06, ct_z + 0.015), mats["wood_walnut"], grp_cart, export_col, bevel=0.006)
    make_box("MSH_Cart_PastryGlass", (0.36, 0.26, 0.24), (cx + 0.14, cy - 0.06, ct_z + 0.15), mats["glass_clear"], grp_cart, export_col, bevel=0.008)
    for cr_i, cr_x in enumerate((0.06, 0.22)):
        make_soft_cushion(f"MSH_Cart_Croissant_{cr_i}", (0.11, 0.07, 0.055), (cx + cr_x, cy - 0.06, ct_z + 0.058), mats["cedar_plank_b"], grp_cart, export_col, rot_deg=(0.0, 0.0, 22.0), puff=0.22, subsurf=1)

    # Brass Gooseneck Kettle & Stacked Ceramic Cups
    make_cylinder("MSH_Cart_PourKettle", 0.068, 0.15, (cx + 0.52, cy + 0.08, ct_z + 0.075), mats["brass"], grp_cart, export_col, r_top=0.046)
    for ci_c in range(2):
        make_cylinder(f"MSH_Cart_LatteCup_{ci_c}", 0.044, 0.08, (cx + 0.50, cy - 0.14, ct_z + 0.04 + ci_c * 0.065), mats["cart_cream"], grp_cart, export_col, r_top=0.052)

    # 2. Striped Cream & Taupe Sun Parasol Umbrella
    grp_parasol = create_hierarchy_node("CLUSTER_Canvas_Parasol", parent=zone, collection=export_col, location=(cx + 0.02, cy + 0.08, ct_z))
    make_cylinder("MSH_Parasol_Pole", 0.028, 1.88, (cx + 0.02, cy + 0.08, ct_z + 0.94), mats["wood_walnut"], grp_parasol, export_col, segs=20)
    _make_parasol_canopy(
        "MSH_Parasol_Canopy",
        (cx + 0.02, cy + 0.08, ct_z + 1.62),
        1.26,
        0.38,
        mats["cart_cream"],
        mats["parasol_taupe"],
        grp_parasol,
        export_col,
    )
    make_soft_cushion("MSH_Parasol_Finial", (0.09, 0.09, 0.12), (cx + 0.02, cy + 0.08, ct_z + 2.04), mats["wood_walnut"], grp_parasol, export_col, puff=0.24, subsurf=1)

    # 3. Lakeside Round Bistro Table & Blossom Vase at (1.95, 2.85, deck_z)
    tx, ty = 1.95, 2.85
    grp_bistro = create_hierarchy_node("CLUSTER_Lakeside_BistroTable", parent=zone, collection=export_col, location=(tx, ty, deck_z))
    make_cylinder("MSH_Bistro_BaseDisc", 0.26, 0.032, (tx, ty, deck_z + 0.016), mats["iron_lamp"], grp_bistro, export_col, segs=28)
    make_cylinder("MSH_Bistro_Pedestal", 0.032, 0.70, (tx, ty, deck_z + 0.37), mats["iron_lamp"], grp_bistro, export_col, segs=20)
    make_cylinder("MSH_Bistro_TableTop", 0.48, 0.036, (tx, ty, deck_z + 0.73), mats["cart_cream"], grp_bistro, export_col, segs=36, bevel=0.010)
    make_torus_ring("MSH_Bistro_BrassRim", 0.48, 0.010, (tx, ty, deck_z + 0.73), mats["brass"], grp_bistro, export_col, major_segs=36, minor_segs=8)
    make_cylinder("MSH_Bistro_BudVase", 0.042, 0.13, (tx - 0.06, ty + 0.04, deck_z + 0.81), mats["balustrade_light"], grp_bistro, export_col, r_top=0.024)
    make_soft_cushion("MSH_Bistro_FlowerBloom", (0.11, 0.11, 0.09), (tx - 0.06, ty + 0.04, deck_z + 0.90), mats["blossom_pink"], grp_bistro, export_col, puff=0.25, subsurf=1)
    make_cylinder("MSH_Bistro_LatteCup", 0.046, 0.065, (tx + 0.14, ty - 0.10, deck_z + 0.78), mats["cart_cream"], grp_bistro, export_col, r_top=0.054)

    return zone


def _build_zone_lakeside_fountain(
    parent_grp: bpy.types.Object,
    export_col: bpy.types.Collection,
    mats: dict[str, bpy.types.Material],
) -> bpy.types.Object:
    """Zone 3: Classical Two-Tier Stone Fountain + Pastel Hydrangea & White Daisy Flowerbeds."""
    fx, fy = 3.22, -0.28
    zone = create_hierarchy_node("ZONE_03_Lakeside_Fountain", parent=parent_grp, collection=export_col, location=(fx, fy, 0.0))

    # 1. Two-Tier Carved Limestone Fountain
    grp_ftn = create_hierarchy_node("CLUSTER_Tiered_Fountain", parent=zone, collection=export_col, location=(fx, fy, 0.0))
    make_cylinder("MSH_Fountain_StepPlinth", 1.18, 0.09, (fx, fy, 0.045), mats["balustrade_cream"], grp_ftn, export_col, segs=40, bevel=0.014)
    make_cylinder("MSH_Fountain_OuterWall", 1.04, 0.34, (fx, fy, 0.24), mats["balustrade_light"], grp_ftn, export_col, segs=40, bevel=0.014)
    make_torus_ring("MSH_Fountain_OuterCoping", 1.04, 0.065, (fx, fy, 0.41), mats["balustrade_cream"], grp_ftn, export_col, major_segs=40, minor_segs=12)
    make_cylinder("MSH_Fountain_LowerWater", 0.98, 0.06, (fx, fy, 0.36), mats["fountain_water"], grp_ftn, export_col, segs=36, bevel=0.0)
    make_torus_ring("MSH_Fountain_WaterRipple", 0.62, 0.012, (fx, fy, 0.395), mats["blossom_ivory"], grp_ftn, export_col, major_segs=32, minor_segs=8)

    # Central pedestal + upper basin + spout finial
    make_cylinder("MSH_Fountain_CenterColumn", 0.24, 0.66, (fx, fy, 0.68), mats["balustrade_cream"], grp_ftn, export_col, segs=24, r_top=0.18)
    make_cylinder("MSH_Fountain_UpperBowl", 0.54, 0.16, (fx, fy, 1.04), mats["balustrade_light"], grp_ftn, export_col, segs=32, r_top=0.58, bevel=0.012)
    make_torus_ring("MSH_Fountain_UpperRim", 0.56, 0.038, (fx, fy, 1.12), mats["balustrade_cream"], grp_ftn, export_col, major_segs=32, minor_segs=10)
    make_cylinder("MSH_Fountain_UpperWater", 0.51, 0.04, (fx, fy, 1.10), mats["fountain_water"], grp_ftn, export_col, segs=28, bevel=0.0)
    make_cylinder("MSH_Fountain_TopSpout", 0.11, 0.28, (fx, fy, 1.26), mats["balustrade_cream"], grp_ftn, export_col, segs=20, r_top=0.06)
    _make_sphere("MSH_Fountain_WaterCrown", 0.11, (fx, fy, 1.44), mats["fountain_water"], grp_ftn, export_col, scale_xyz=(1.0, 1.0, 0.88))

    # 2. Hydrangea & White Daisy Flowerbeds Flanking the Fountain & Balustrade
    grp_flowers = create_hierarchy_node("CLUSTER_Hydrangea_Flowerbeds", parent=zone, collection=export_col, location=(fx, fy, 0.0))
    hydrangea_clusters = [
        (fx - 0.55, fy + 1.18, 1.05, "hydrangea_blue"),
        (fx - 0.12, fy + 1.32, 0.92, "hydrangea_lavender"),
        (fx + 0.96, fy - 0.86, 1.08, "hydrangea_blue"),
        (fx + 1.18, fy - 0.42, 0.90, "hydrangea_lavender"),
    ]
    for h_idx, (hx, hy, sc, hmat) in enumerate(hydrangea_clusters):
        _make_blossom_cloud(
            f"MSH_Hydrangea_FoliageMound_{h_idx:02d}",
            (0.36 * sc, 0.34 * sc, 0.22 * sc),
            (hx, hy, 0.18 * sc),
            h_idx + 20,
            mats["leaf_fresh"] if h_idx % 2 == 0 else mats["hedge_deep"],
            grp_flowers,
            export_col,
        )
        for li in range(5):
            la = li * 1.256 + h_idx
            make_curved_leaf(
                f"MSH_Hydrangea_Leaf_{h_idx}_{li}",
                0.26 * sc,
                0.16 * sc,
                0.06 * sc,
                (hx + math.cos(la) * 0.18 * sc, hy + math.sin(la) * 0.18 * sc, 0.24 * sc),
                (28.0, 0.0, math.degrees(la) - 90.0),
                mats["leaf_fresh"],
                grp_flowers,
                export_col,
            )
        for bi_h, (bx_o, by_o, bz_o) in enumerate(((-0.14, -0.06, 0.40), (0.14, 0.08, 0.42), (0.0, -0.14, 0.46), (-0.04, 0.14, 0.38))):
            _make_blossom_cloud(
                f"MSH_Hydrangea_Bloom_{h_idx}_{bi_h}",
                (0.135 * sc, 0.135 * sc, 0.115 * sc),
                (hx + bx_o * sc, hy + by_o * sc, bz_o * sc),
                h_idx * 7 + bi_h,
                mats[hmat if bi_h % 2 == 0 else ("hydrangea_lavender" if hmat == "hydrangea_blue" else "hydrangea_blue")],
                grp_flowers,
                export_col,
            )

    # Crisp White Daisies near front-right of fountain
    for di, (dx_o, dy_o) in enumerate(((0.76, -1.16), (0.98, -1.24), (1.16, -1.04), (0.86, -1.36), (1.08, -1.38))):
        dx, dy = fx + dx_o, fy + dy_o
        make_capsule_tube(f"MSH_Daisy_Stem_{di}", (dx, dy, 0.02), (dx, dy, 0.34), 0.012, 0.010, mats["leaf_fresh"], grp_flowers, export_col)
        make_cylinder(f"MSH_Daisy_Petals_{di}", 0.095, 0.018, (dx, dy, 0.35), mats["cart_cream"], grp_flowers, export_col, segs=16, rot_deg=(12.0, -8.0, di * 25.0))
        make_soft_cushion(f"MSH_Daisy_Core_{di}", (0.055, 0.055, 0.036), (dx, dy, 0.365), mats["brass"], grp_flowers, export_col, puff=0.24, subsurf=1)

    return zone


def build_interactive_zones_and_lights(
    root_node: bpy.types.Object,
    export_col: bpy.types.Collection,
    mats: dict[str, bpy.types.Material],
) -> None:
    """Build all 3 outdoor interactive zones plus 4 vintage park lampposts & overhead festoon string lights."""
    grp_zones = create_hierarchy_node("GRP_02_Interactive_Zones", parent=root_node, collection=export_col)
    _build_zone_blossom_bench(grp_zones, export_col, mats)
    _build_zone_coffee_cart(grp_zones, export_col, mats)
    _build_zone_lakeside_fountain(grp_zones, export_col, mats)

    # Vintage Park Lampposts & Overhead Festoon String Lights (matches Concept 01 & Concept 03!)
    grp_lamps = create_hierarchy_node("GRP_03_Lighting_And_Foliage", parent=root_node, collection=export_col)
    lamp_coords = [
        (-4.55, -0.95, 0.0, "WalkwayLeft"),
        (-1.42, 3.28, 0.16, "DeckBackLeft"),
        (1.05, 4.35, 0.16, "DeckCenter"),
        (3.36, 2.18, 0.16, "DeckRight"),
    ]
    lantern_tops: list[tuple[float, float, float]] = []

    for lx, ly, lz, tag in lamp_coords:
        grp_lp = create_hierarchy_node(f"CLUSTER_Lamppost_{tag}", parent=grp_lamps, collection=export_col, location=(lx, ly, lz))
        make_cylinder(f"MSH_Lamp_{tag}_BasePlinth", 0.17, 0.24, (lx, ly, lz + 0.12), mats["iron_lamp"], grp_lp, export_col, segs=18)
        make_cylinder(f"MSH_Lamp_{tag}_FlutedCollar", 0.12, 0.36, (lx, ly, lz + 0.40), mats["iron_lamp"], grp_lp, export_col, segs=18, r_top=0.075)
        make_cylinder(f"MSH_Lamp_{tag}_Shaft", 0.055, 2.15, (lx, ly, lz + 1.64), mats["iron_lamp"], grp_lp, export_col, segs=16, r_top=0.042)
        make_box(f"MSH_Lamp_{tag}_CrossArm", (0.44, 0.045, 0.045), (lx, ly, lz + 2.58), mats["iron_lamp"], grp_lp, export_col, bevel=0.008)
        # Glowing lantern glass housing + iron cap
        make_cylinder(f"MSH_Lamp_{tag}_LanternBase", 0.11, 0.06, (lx, ly, lz + 2.74), mats["iron_lamp"], grp_lp, export_col, segs=8, r_top=0.14)
        make_cylinder(f"MSH_Lamp_{tag}_GlassGlow", 0.13, 0.30, (lx, ly, lz + 2.92), mats["bulb_warm_glow"], grp_lp, export_col, segs=8, r_top=0.16)
        make_cylinder(f"MSH_Lamp_{tag}_RoofCap", 0.20, 0.14, (lx, ly, lz + 3.14), mats["iron_lamp"], grp_lp, export_col, segs=8, r_top=0.02)
        lantern_tops.append((lx, ly, lz + 2.72))

    # Catenary Festoon String-Light Cables + Warm Edison Bulbs spanning across the lampposts
    spans = [(0, 1, 8), (1, 2, 7), (2, 3, 7)]
    for s_idx, (ia, ib, bulb_n) in enumerate(spans):
        ax, ay, az = lantern_tops[ia]
        bx, by, bz = lantern_tops[ib]
        grp_span = create_hierarchy_node(f"CLUSTER_FestoonSpan_{s_idx:02d}", parent=grp_lamps, collection=export_col)
        seg_n = 12
        pts: list[tuple[float, float, float]] = []
        for k in range(seg_n + 1):
            t = k / seg_n
            sag = 4.0 * t * (1.0 - t) * 0.34
            pts.append((ax + (bx - ax) * t, ay + (by - ay) * t, az + (bz - az) * t - sag))
        for k in range(seg_n):
            make_capsule_tube(
                f"MSH_Festoon_{s_idx:02d}_Wire_{k:02d}",
                pts[k],
                pts[k + 1],
                0.011,
                0.011,
                mats["iron_lamp"],
                grp_span,
                export_col,
                segments=10,
                steps=2,
            )
        for bi_f in range(bulb_n):
            tb = (bi_f + 1) / (bulb_n + 1)
            sag = 4.0 * tb * (1.0 - tb) * 0.34
            bx_p = ax + (bx - ax) * tb
            by_p = ay + (by - ay) * tb
            bz_p = az + (bz - az) * tb - sag
            make_cylinder(f"MSH_Festoon_{s_idx:02d}_Socket_{bi_f:02d}", 0.018, 0.04, (bx_p, by_p, bz_p - 0.025), mats["iron_lamp"], grp_span, export_col, segs=12)
            _make_sphere(
                f"MSH_Festoon_{s_idx:02d}_Bulb_{bi_f:02d}",
                0.038,
                (bx_p, by_p, bz_p - 0.072),
                mats["bulb_warm_glow"],
                grp_span,
                export_col,
                scale_xyz=(0.88, 0.88, 1.15),
                u_segs=14,
                v_segs=10,
            )
