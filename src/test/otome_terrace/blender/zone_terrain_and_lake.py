# -*- coding: utf-8 -*-
"""Stage Module 1: Open-Air Park Lawn, Curved Cobblestone Walkway, Raised Lakeside Cedar Deck, Stone Balustrade, Lake & Distant Hills."""

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
    make_cylinder,
    make_soft_cushion,
)


def _eval_cubic_bezier_2d(
    p0: tuple[float, float],
    p1: tuple[float, float],
    p2: tuple[float, float],
    p3: tuple[float, float],
    t: float,
) -> tuple[float, float]:
    u = 1.0 - t
    x = u * u * u * p0[0] + 3.0 * u * u * t * p1[0] + 3.0 * u * t * t * p2[0] + t * t * t * p3[0]
    y = u * u * u * p0[1] + 3.0 * u * u * t * p1[1] + 3.0 * u * t * t * p2[1] + t * t * t * p3[1]
    return (x, y)


def _make_ribbon_walkway(
    name: str,
    ctrl_pts: tuple[tuple[float, float], tuple[float, float], tuple[float, float], tuple[float, float]],
    half_width: float,
    height_z: float,
    thickness: float,
    steps: int,
    mat: bpy.types.Material,
    parent: bpy.types.Object,
    col: bpy.types.Collection,
) -> tuple[bpy.types.Object, list[tuple[float, float, float, float]]]:
    """Loft a smooth curved stone walkway ribbon and return sampled (x, y, nx, ny) spine frames."""
    bm = bmesh.new()
    top_l: list[bmesh.types.BMVert] = []
    top_r: list[bmesh.types.BMVert] = []
    bot_l: list[bmesh.types.BMVert] = []
    bot_r: list[bmesh.types.BMVert] = []
    frames: list[tuple[float, float, float, float]] = []

    p0, p1, p2, p3 = ctrl_pts
    for i in range(steps + 1):
        t = i / steps
        cx, cy = _eval_cubic_bezier_2d(p0, p1, p2, p3, t)
        dt = 0.004
        t_a = max(0.0, t - dt)
        t_b = min(1.0, t + dt)
        ax, ay = _eval_cubic_bezier_2d(p0, p1, p2, p3, t_a)
        bx, by = _eval_cubic_bezier_2d(p0, p1, p2, p3, t_b)
        tx, ty = bx - ax, by - ay
        tlen = max(1e-5, math.hypot(tx, ty))
        tx, ty = tx / tlen, ty / tlen
        nx, ny = -ty, tx
        frames.append((cx, cy, nx, ny))

        # Slight graceful flare at foreground entry
        flare = 1.0 + 0.16 * max(0.0, 1.0 - t * 2.4)
        hw = half_width * flare
        lx, ly = cx - nx * hw, cy - ny * hw
        rx, ry = cx + nx * hw, cy + ny * hw

        top_l.append(bm.verts.new((lx, ly, height_z)))
        top_r.append(bm.verts.new((rx, ry, height_z)))
        bot_l.append(bm.verts.new((lx, ly, height_z - thickness)))
        bot_r.append(bm.verts.new((rx, ry, height_z - thickness)))

    for i in range(steps):
        bm.faces.new((top_l[i], top_r[i], top_r[i + 1], top_l[i + 1]))
        bm.faces.new((bot_r[i], bot_l[i], bot_l[i + 1], bot_r[i + 1]))
        bm.faces.new((bot_l[i], top_l[i], top_l[i + 1], bot_l[i + 1]))
        bm.faces.new((top_r[i], bot_r[i], bot_r[i + 1], top_r[i + 1]))

    bm.faces.new((bot_l[0], bot_r[0], top_r[0], top_l[0]))
    bm.faces.new((top_l[-1], top_r[-1], bot_r[-1], bot_l[-1]))

    obj = _finalize_mesh_object(name, bm, (0.0, 0.0, 0.0), (0.0, 0.0, 0.0), mat, parent, col, bevel_width=0.008)
    return obj, frames


def _build_balustrade_segment(
    seg_id: str,
    p_start: tuple[float, float],
    p_end: tuple[float, float],
    base_z: float,
    parent: bpy.types.Object,
    col: bpy.types.Collection,
    mats: dict[str, bpy.types.Material],
    add_end_pier: bool = True,
) -> None:
    """Classical carved cream-limestone lakeside balustrade segment with turned balusters & piers."""
    grp = create_hierarchy_node(f"GRP_Balustrade_{seg_id}", parent=parent, collection=col)
    x0, y0 = p_start
    x1, y1 = p_end
    dx, dy = x1 - x0, y1 - y0
    seg_len = math.hypot(dx, dy)
    yaw_deg = math.degrees(math.atan2(dy, dx))
    mx, my = (x0 + x1) * 0.5, (y0 + y1) * 0.5

    # Bottom plinth & top coping rail
    make_box(
        f"MSH_Balustrade_{seg_id}_Plinth",
        (seg_len, 0.24, 0.14),
        (mx, my, base_z + 0.07),
        mats["balustrade_cream"],
        grp,
        col,
        bevel=0.012,
        rot_deg=(0.0, 0.0, yaw_deg),
    )
    make_box(
        f"MSH_Balustrade_{seg_id}_TopRail",
        (seg_len + 0.04, 0.28, 0.11),
        (mx, my, base_z + 0.80),
        mats["balustrade_light"],
        grp,
        col,
        bevel=0.014,
        rot_deg=(0.0, 0.0, yaw_deg),
    )

    # Turned classical balusters spaced ~0.34m apart
    count = max(2, int((seg_len - 0.50) / 0.34))
    for i in range(count):
        t = (i + 1) / (count + 1)
        bx = x0 + dx * t
        by = y0 + dy * t
        make_cylinder(
            f"MSH_Baluster_{seg_id}_{i:02d}_Lower",
            0.052,
            0.28,
            (bx, by, base_z + 0.28),
            mats["balustrade_cream"],
            grp,
            col,
            segs=18,
            r_top=0.034,
        )
        make_soft_cushion(
            f"MSH_Baluster_{seg_id}_{i:02d}_Belly",
            (0.115, 0.115, 0.16),
            (bx, by, base_z + 0.36),
            mats["balustrade_light"],
            grp,
            col,
            puff=0.22,
            subsurf=1,
        )
        make_cylinder(
            f"MSH_Baluster_{seg_id}_{i:02d}_Upper",
            0.032,
            0.30,
            (bx, by, base_z + 0.60),
            mats["balustrade_cream"],
            grp,
            col,
            segs=18,
            r_top=0.048,
        )

    # Start pier (and optional end pier) with carved finial ball
    pier_pts = [(x0, y0, "Start")]
    if add_end_pier:
        pier_pts.append((x1, y1, "End"))
    for px, py, tag in pier_pts:
        make_box(
            f"MSH_Balustrade_{seg_id}_PierBase_{tag}",
            (0.38, 0.38, 0.18),
            (px, py, base_z + 0.09),
            mats["balustrade_cream"],
            grp,
            col,
            bevel=0.014,
            rot_deg=(0.0, 0.0, yaw_deg),
        )
        make_box(
            f"MSH_Balustrade_{seg_id}_PierShaft_{tag}",
            (0.32, 0.32, 0.72),
            (px, py, base_z + 0.52),
            mats["balustrade_light"],
            grp,
            col,
            bevel=0.012,
            rot_deg=(0.0, 0.0, yaw_deg),
        )
        make_box(
            f"MSH_Balustrade_{seg_id}_PierCap_{tag}",
            (0.40, 0.40, 0.09),
            (px, py, base_z + 0.91),
            mats["balustrade_cream"],
            grp,
            col,
            bevel=0.012,
            rot_deg=(0.0, 0.0, yaw_deg),
        )
        bm_fin = bmesh.new()
        bmesh.ops.create_uvsphere(bm_fin, u_segments=20, v_segments=12, radius=0.095)
        _finalize_mesh_object(
            f"MSH_Balustrade_{seg_id}_Finial_{tag}",
            bm_fin,
            (px, py, base_z + 1.04),
            (0.0, 0.0, 0.0),
            mats["balustrade_light"],
            grp,
            col,
        )


def build_open_air_terrain_and_horizon(
    root_node: bpy.types.Object,
    export_col: bpy.types.Collection,
    mats: dict[str, bpy.types.Material],
) -> bpy.types.Object:
    """Build open-air park lawn, curved cobblestone walkway, raised cedar deck, lakeside balustrade & distant hills."""
    grp_terrain = create_hierarchy_node("GRP_01_OpenAir_Terrain", parent=root_node, collection=export_col)
    grp_lawn = create_hierarchy_node("GRP_Lawn_And_Walkway", parent=grp_terrain, collection=export_col)
    grp_deck = create_hierarchy_node("GRP_Lakeside_CedarDeck", parent=grp_terrain, collection=export_col)
    grp_bal = create_hierarchy_node("GRP_Lakeside_Balustrade", parent=grp_terrain, collection=export_col)
    grp_vista = create_hierarchy_node("GRP_Scenic_Lake_And_Hills", parent=grp_terrain, collection=export_col)

    # 1. Lush Open-Air Emerald Park Lawn + Stone Retaining Seawall Facing Lake
    make_box(
        "MSH_Park_StoneSeawall",
        (16.8, 10.2, 0.62),
        (0.0, -1.25, -0.32),
        mats["cobble_warm_b"],
        grp_lawn,
        export_col,
        bevel=0.025,
    )
    make_box(
        "MSH_Park_MainLawn",
        (16.4, 9.8, 0.08),
        (0.0, -1.30, -0.04),
        mats["grass_fresh"],
        grp_lawn,
        export_col,
        bevel=0.020,
    )
    # Soft sunlit grass lawn patches for painterly anime variation
    for idx, (gx, gy, gw, gd, rot_z) in enumerate(
        (
            (-3.6, 0.6, 4.4, 3.6, 12.0),
            (2.8, -1.8, 4.2, 3.4, -15.0),
            (-4.2, -3.0, 3.6, 2.6, 8.0),
        )
    ):
        make_soft_cushion(
            f"MSH_Lawn_SoftMound_{idx:02d}",
            (gw, gd, 0.036),
            (gx, gy, 0.002),
            mats["grass_soft"],
            grp_lawn,
            export_col,
            rot_deg=(0.0, 0.0, rot_z),
            puff=0.06,
            subsurf=1,
        )

    # Soft lush perimeter hedges on far-left & foreground-left (natural soft boundary, zero walls!)
    hedge_spots = [
        (-6.2, 2.7, 1.5, 1.1, 0.78, 12.0),
        (-6.4, 1.3, 1.4, 1.3, 0.86, -8.0),
        (-6.3, -0.3, 1.3, 1.4, 0.74, 6.0),
        (-5.9, -2.0, 1.4, 1.2, 0.70, 18.0),
        (5.5, -3.4, 1.5, 1.1, 0.68, -22.0),
    ]
    for hi, (hx, hy, hw, hd, hh, hrot) in enumerate(hedge_spots):
        bm_hdg = bmesh.new()
        bmesh.ops.create_icosphere(bm_hdg, subdivisions=3, radius=0.5)
        for v in bm_hdg.verts:
            bump = 1.0 + 0.14 * math.sin(v.co.x * 7.2 + hi) * math.cos(v.co.y * 6.8) * math.cos(v.co.z * 5.4)
            v.co = Vector((v.co.x * hw * bump, v.co.y * hd * bump, v.co.z * hh * bump))
        _finalize_mesh_object(
            f"MSH_Perimeter_Hedge_{hi:02d}",
            bm_hdg,
            (hx, hy, hh * 0.44),
            (0.0, 0.0, hrot),
            mats["hedge_deep"] if hi % 2 == 0 else mats["leaf_fresh"],
            grp_lawn,
            export_col,
        )

    # 2. Winding Curved Warm Cobblestone Walkway (matches Concept 03 S-curve!)
    _, main_frames = _make_ribbon_walkway(
        "MSH_Walkway_MainBase",
        ((-3.85, -4.65), (-2.55, -2.10), (-0.55, -0.55), (0.55, 1.62)),
        0.96,
        0.022,
        0.05,
        28,
        mats["cobble_mortar"],
        grp_lawn,
        export_col,
    )
    # Branch path leading gently toward the Lakeside Fountain Overlook
    _, branch_frames = _make_ribbon_walkway(
        "MSH_Walkway_FountainBranch",
        ((-0.65, -0.65), (0.55, -0.78), (1.65, -0.58), (2.55, -0.25)),
        0.68,
        0.020,
        0.045,
        16,
        mats["cobble_mortar"],
        grp_lawn,
        export_col,
    )

    # Sculpted individual beveled cobblestones & raised side curbs along main S-curve
    cobble_mats = [mats["cobble_warm_a"], mats["cobble_warm_b"], mats["cobble_curb"]]
    stone_idx = 0
    for step_i, (cx, cy, nx, ny) in enumerate(main_frames):
        tx, ty = ny, -nx
        yaw_deg = math.degrees(math.atan2(ty, tx))
        flare = 1.0 + 0.16 * max(0.0, 1.0 - (step_i / max(1, len(main_frames) - 1)) * 2.4)
        hw = 0.96 * flare
        # Left & right raised stone curbs every 2 steps
        if step_i % 2 == 0 and step_i < len(main_frames) - 1:
            for side_s, tag in ((-1.0, "L"), (1.0, "R")):
                kx = cx + nx * (hw + 0.06) * side_s
                ky = cy + ny * (hw + 0.06) * side_s
                make_box(
                    f"MSH_Path_Curb_{step_i:02d}_{tag}",
                    (0.42, 0.13, 0.055),
                    (kx, ky, 0.024),
                    mats["cobble_curb"],
                    grp_lawn,
                    export_col,
                    bevel=0.010,
                    rot_deg=(0.0, 0.0, yaw_deg),
                )
        # Staggered cobblestone tiles across walkway width
        row_offsets = (-0.64, -0.22, 0.22, 0.64) if (step_i % 2 == 0) else (-0.44, 0.0, 0.44)
        for ro in row_offsets:
            sx = cx + nx * (ro * flare)
            sy = cy + ny * (ro * flare)
            sw = 0.28 + (stone_idx % 3) * 0.03
            sd = 0.30 + ((stone_idx + 1) % 2) * 0.04
            make_box(
                f"MSH_Cobble_Tile_{stone_idx:03d}",
                (sw, sd, 0.020),
                (sx, sy, 0.026),
                cobble_mats[stone_idx % 3],
                grp_lawn,
                export_col,
                bevel=0.007,
                rot_deg=(0.0, 0.0, yaw_deg + ((stone_idx % 5) - 2) * 2.5),
            )
            stone_idx += 1

    for b_i, (cx, cy, nx, ny) in enumerate(branch_frames):
        if b_i < 3:
            continue
        tx, ty = ny, -nx
        yaw_deg = math.degrees(math.atan2(ty, tx))
        for ro in (-0.32, 0.0, 0.32):
            sx = cx + nx * ro
            sy = cy + ny * ro
            make_box(
                f"MSH_Cobble_BranchTile_{stone_idx:03d}",
                (0.26, 0.26, 0.018),
                (sx, sy, 0.024),
                cobble_mats[stone_idx % 3],
                grp_lawn,
                export_col,
                bevel=0.006,
                rot_deg=(0.0, 0.0, yaw_deg),
            )
            stone_idx += 1

    # 3. Raised Lakeside Cedar-Wood Coffee Deck (X in [-1.45, +3.55], Y in [+1.55, +4.55], Top Z = 0.16)
    deck_x0, deck_x1 = -1.45, 3.55
    deck_y0, deck_y1 = 1.55, 4.55
    deck_cx = (deck_x0 + deck_x1) * 0.5
    deck_cy = (deck_y0 + deck_y1) * 0.5
    deck_w = deck_x1 - deck_x0
    deck_d = deck_y1 - deck_y0

    make_box(
        "MSH_CedarDeck_Subframe",
        (deck_w + 0.08, deck_d + 0.08, 0.24),
        (deck_cx, deck_cy, 0.015),
        mats["wood_walnut"],
        grp_deck,
        export_col,
        bevel=0.012,
    )
    plank_rows = 16
    plank_depth = deck_d / plank_rows
    cedar_mats = [mats["cedar_plank_a"], mats["cedar_plank_b"], mats["wood_oak_warm"]]
    for pr in range(plank_rows):
        pyc = deck_y0 + (pr + 0.5) * plank_depth
        split_x = deck_cx + (0.45 if pr % 2 == 0 else -0.55)
        for seg_idx, (px_a, px_b) in enumerate(((deck_x0, split_x - 0.01), (split_x + 0.01, deck_x1))):
            make_box(
                f"MSH_CedarDeck_Plank_{pr:02d}_{seg_idx}",
                (px_b - px_a, plank_depth - 0.014, 0.036),
                ((px_a + px_b) * 0.5, pyc, 0.142),
                cedar_mats[(pr + seg_idx) % 3],
                grp_deck,
                export_col,
                bevel=0.006,
            )

    # Wide Welcoming Entry Steps onto Cedar Deck (centered at X = 0.55, Y = 1.38)
    make_box(
        "MSH_CedarDeck_StepLower",
        (2.15, 0.38, 0.085),
        (0.55, 1.36, 0.042),
        mats["cedar_plank_b"],
        grp_deck,
        export_col,
        bevel=0.010,
    )
    make_box(
        "MSH_CedarDeck_StepTrim",
        (deck_w + 0.12, 0.08, 0.05),
        (deck_cx, deck_y0 - 0.02, 0.142),
        mats["wood_walnut"],
        grp_deck,
        export_col,
        bevel=0.008,
    )

    # 4. Classical Cream Lakeside Balustrade Framing the Waterfront
    _build_balustrade_segment("BackLeft", (-5.80, 3.45), (-1.48, 3.45), 0.0, grp_bal, export_col, mats, add_end_pier=True)
    _build_balustrade_segment("DeckLeftSide", (-1.45, 3.48), (-1.45, 4.52), 0.15, grp_bal, export_col, mats, add_end_pier=False)
    _build_balustrade_segment("DeckWaterfront", (-1.45, 4.52), (3.52, 4.52), 0.15, grp_bal, export_col, mats, add_end_pier=True)
    _build_balustrade_segment("DeckRightSide", (3.52, 4.52), (3.52, 1.62), 0.15, grp_bal, export_col, mats, add_end_pier=True)
    _build_balustrade_segment("RightPromenade", (3.55, 1.58), (5.85, -2.55), 0.0, grp_bal, export_col, mats, add_end_pier=True)

    # 5. Shimmering Open Lake Water Plane & Layered Distant Rolling Green Hills
    make_box(
        "MSH_Scenic_LakeBed",
        (76.0, 52.0, 0.12),
        (0.0, 24.0, -0.78),
        mats["lake_deep"],
        grp_vista,
        export_col,
        bevel=0.0,
    )
    make_box(
        "MSH_Scenic_LakeWater",
        (76.0, 52.0, 0.06),
        (0.0, 24.0, -0.42),
        mats["lake_surface"],
        grp_vista,
        export_col,
        bevel=0.0,
    )

    # Distant shoreline & soft rolling pastoral hills across the lake (Y = 23..35m)
    hill_specs = [
        (-13.5, 24.5, 13.5, 5.5, 3.6, "hill_near"),
        (-1.2, 26.5, 14.5, 6.0, 4.4, "hill_mid"),
        (11.8, 24.0, 13.0, 5.2, 3.5, "hill_near"),
        (-7.5, 32.0, 17.5, 6.8, 6.2, "hill_far"),
        (8.2, 33.0, 18.0, 7.0, 6.6, "hill_far"),
    ]
    for hi, (hx, hy, rx, ry, rz, mat_key) in enumerate(hill_specs):
        bm_h = bmesh.new()
        bmesh.ops.create_icosphere(bm_h, subdivisions=3, radius=1.0)
        for v in bm_h.verts:
            lobe = 1.0 + 0.08 * math.sin(v.co.x * 3.1 + hi) * math.cos(v.co.y * 2.7)
            v.co = Vector((v.co.x * rx * lobe, v.co.y * ry * lobe, max(-0.25, v.co.z) * rz))
        _finalize_mesh_object(
            f"MSH_Distant_Hill_{hi:02d}",
            bm_h,
            (hx, hy, -0.55),
            (0.0, 0.0, 0.0),
            mats[mat_key],
            grp_vista,
            export_col,
        )

    return grp_terrain
