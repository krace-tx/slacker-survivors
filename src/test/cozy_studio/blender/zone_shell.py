# -*- coding: utf-8 -*-
"""Stage 4 Module 1: High-Craft Loft Atelier Shell (8.8x7.8m Floor, 4.15m Wainscoted Walls, Ceiling Beams, French Windows & Draped Curtains)."""

from __future__ import annotations

import math
import bpy
from blender_core import (
    create_hierarchy_node,
    make_box,
    make_capsule_tube,
    make_curved_leaf,
    make_cylinder,
    make_draped_curtain,
    make_soft_cushion,
    make_torus_ring,
)


def build_building_shell(
    root_node: bpy.types.Object,
    export_col: bpy.types.Collection,
    mats: dict[str, bpy.types.Material],
) -> bpy.types.Object:
    """
    Build spacious 8.80m x 7.80m x 4.15m Cozy Anime Atelier Shell:
    - Floor extent: X in [-4.40, +4.40], Y in [-3.90, +3.90], top at Z = 0.0.
    - Back Loft Wall at Y = +3.90 (height 4.15m); Left Window Wall at X = -4.40 (height 4.15m).
    - Panelled oak wainscoting, picture rail, exposed timber ceiling beams, 2 tall multi-pane
      French studio windows with exterior flower boxes & draped linen curtains.
    """
    grp_shell = create_hierarchy_node("GRP_01_Building_Shell", parent=root_node, collection=export_col)
    grp_floor = create_hierarchy_node("GRP_Floors_And_Base", parent=grp_shell, collection=export_col)
    grp_walls = create_hierarchy_node("GRP_Walls_Wainscot_And_Beams", parent=grp_shell, collection=export_col)
    grp_windows = create_hierarchy_node("GRP_French_Windows_And_Curtains", parent=grp_shell, collection=export_col)

    # 1. Surrounding Warm Tatami/Terrace Rim + Walnut Diorama Plinth + 26x4 Staggered Honey-Oak Planks
    make_box(
        "MSH_Floor_DioramaPlinth",
        (9.16, 8.16, 0.18),
        (0.0, 0.0, -0.105),
        mats["wood_walnut"],
        grp_floor,
        export_col,
        bevel=0.018,
    )
    make_box(
        "MSH_Floor_SubDeck",
        (8.88, 7.88, 0.024),
        (0.0, 0.0, -0.020),
        mats["wood_walnut"],
        grp_floor,
        export_col,
        bevel=0.008,
    )

    num_rows = 24
    plank_w = 7.80 / num_rows
    plank_mats = [mats["wood_oak"], mats["wood_oak_light"], mats["wood_oak_warm"], mats["wood_oak"]]
    for r in range(num_rows):
        yc = -3.90 + (r + 0.5) * plank_w
        shift = 0.55 if (r % 2 == 1) else -0.42
        splits = [-4.40, -2.15 + shift * 0.4, 0.15 - shift * 0.3, 2.35 + shift * 0.35, 4.40]
        for idx in range(4):
            x0, x1 = splits[idx], splits[idx + 1]
            mat_pick = plank_mats[(r * 3 + idx) % len(plank_mats)]
            make_box(
                f"MSH_Floor_Plank_{r:02d}_{idx:02d}",
                ((x1 - x0) - 0.007, plank_w - 0.007, 0.018),
                (0.5 * (x0 + x1), yc, -0.009),
                mat_pick,
                grp_floor,
                export_col,
                bevel=0.0025,
                segs=2,
            )

    # 2. Tall Back Loft Wall (Y = +3.90 .. +4.12, X = -4.62 .. +4.40, Z = 0.0 .. 4.15)
    wall_t = 0.22
    wall_h = 4.15
    make_box(
        "MSH_Wall_Back_Main",
        (9.02, wall_t, wall_h),
        (-0.11, 4.01, wall_h * 0.5),
        mats["wall_cream"],
        grp_walls,
        export_col,
        bevel=0.012,
    )
    # Back Wall Oak Wainscoting (Z = 0.0 .. 0.88) + Baseboard + Recessed Molding Frames + Chair Rail
    make_box("MSH_Wall_Back_Baseboard", (8.80, 0.045, 0.12), (0.0, 3.882, 0.06), mats["wood_walnut"], grp_walls, export_col, bevel=0.006)
    make_box("MSH_Wall_Back_WainscotBacking", (8.80, 0.024, 0.76), (0.0, 3.890, 0.50), mats["wood_oak"], grp_walls, export_col, bevel=0.004)
    for wp_i in range(9):
        px = -3.92 + wp_i * 0.98
        make_box(
            f"MSH_Wall_Back_WainscotPanel_{wp_i:02d}",
            (0.76, 0.018, 0.54),
            (px, 3.874, 0.50),
            mats["wood_oak_light"],
            grp_walls,
            export_col,
            bevel=0.005,
        )
    make_box("MSH_Wall_Back_ChairRail", (8.82, 0.058, 0.052), (0.0, 3.876, 0.90), mats["wood_walnut"], grp_walls, export_col, bevel=0.008)
    make_box("MSH_Wall_Back_PictureRail", (8.82, 0.042, 0.038), (0.0, 3.882, 3.38), mats["wood_oak_warm"], grp_walls, export_col, bevel=0.005)
    make_box("MSH_Wall_Back_CrownBeam", (9.08, 0.28, 0.16), (-0.11, 4.00, 4.19), mats["wood_walnut"], grp_walls, export_col, bevel=0.014)

    # Corner Timber Pillar at Back-Left (-4.40, +3.90) & Back-Right Pilaster (+4.32, +3.90)
    make_box("MSH_Pillar_CornerBL", (0.20, 0.20, wall_h + 0.08), (-4.34, 3.84, (wall_h + 0.08) * 0.5), mats["wood_walnut"], grp_walls, export_col, bevel=0.012)
    make_box("MSH_Pillar_CornerBR", (0.18, 0.18, wall_h + 0.08), (4.31, 3.84, (wall_h + 0.08) * 0.5), mats["wood_walnut"], grp_walls, export_col, bevel=0.012)

    # Exposed Loft Timber Ceiling Rafters & Corbels along top of Back Wall (adds rich architectural height!)
    for rb_i in range(6):
        rx = -3.50 + rb_i * 1.40
        make_box(
            f"MSH_Loft_Rafter_{rb_i:02d}",
            (0.11, 1.15, 0.15),
            (rx, 3.32, 3.98),
            mats["wood_walnut"],
            grp_walls,
            export_col,
            bevel=0.010,
        )
        make_box(
            f"MSH_Loft_Corbel_{rb_i:02d}",
            (0.08, 0.42, 0.09),
            (rx, 3.68, 3.74),
            mats["wood_oak_warm"],
            grp_walls,
            export_col,
            bevel=0.008,
            rot_deg=(36.0, 0.0, 0.0),
        )

    # 3. Tall Left Window Wall (X = -4.62 .. -4.40, Y = -3.90 .. +3.90, Z = 0.0 .. 4.15)
    # Two grand French Studio Windows:
    # Window 01 (Front-Left): Y in [-2.55, -0.55], Z in [0.74, 3.36] (2.00m wide x 2.62m tall!)
    # Window 02 (Back-Left):  Y in [+0.15, +2.15], Z in [0.74, 3.36] (2.00m wide x 2.62m tall!)
    make_box("MSH_Wall_Left_LowerBand", (wall_t, 7.80, 0.74), (-4.51, 0.0, 0.37), mats["wall_cream"], grp_walls, export_col, bevel=0.010)
    make_box("MSH_Wall_Left_UpperHeader", (wall_t, 7.80, 0.79), (-4.51, 0.0, 3.755), mats["wall_cream"], grp_walls, export_col, bevel=0.010)

    piers = [(-3.90, -2.55, "Front"), (-0.55, 0.15, "Mid"), (2.15, 3.90, "Back")]
    for y0, y1, tag in piers:
        make_box(
            f"MSH_Wall_Left_Pier_{tag}",
            (wall_t, y1 - y0, 2.62),
            (-4.51, 0.5 * (y0 + y1), 2.05),
            mats["wall_cream"],
            grp_walls,
            export_col,
            bevel=0.010,
        )

    # Left Wall Interior Wainscoting, Recessed Panels & Deep Oak Window Sill
    make_box("MSH_Wall_Left_Baseboard", (0.045, 7.80, 0.12), (-4.382, 0.0, 0.06), mats["wood_walnut"], grp_walls, export_col, bevel=0.006)
    make_box("MSH_Wall_Left_WainscotBacking", (0.024, 7.80, 0.60), (-4.390, 0.0, 0.42), mats["wood_oak"], grp_walls, export_col, bevel=0.004)
    for lp_i in range(8):
        py = -3.40 + lp_i * 0.97
        make_box(
            f"MSH_Wall_Left_WainscotPanel_{lp_i:02d}",
            (0.018, 0.74, 0.44),
            (-4.374, py, 0.42),
            mats["wood_oak_light"],
            grp_walls,
            export_col,
            bevel=0.005,
        )
    make_box("MSH_Wall_Left_DeepSill", (0.22, 7.82, 0.048), (-4.36, 0.0, 0.745), mats["wood_walnut"], grp_walls, export_col, bevel=0.008)
    make_box("MSH_Wall_Left_CrownBeam", (0.28, 8.08, 0.16), (-4.50, 0.08, 4.19), mats["wood_walnut"], grp_walls, export_col, bevel=0.014)
    make_box("MSH_Pillar_CornerFL", (0.18, 0.18, wall_h + 0.08), (-4.34, -3.81, (wall_h + 0.08) * 0.5), mats["wood_walnut"], grp_walls, export_col, bevel=0.012)

    # 4. Grand Multi-Pane French Studio Windows + Transom Bars + Exterior Flower Boxes + Flowing Curtains
    win_bays = [(-2.55, -0.55, "01"), (0.15, 2.15, "02")]
    for y0, y1, wid in win_bays:
        yc = 0.5 * (y0 + y1)
        bw = y1 - y0  # 2.00m
        bh = 2.62     # Z = 0.74 .. 3.36
        zc = 2.05

        # Outer & inner wooden casing frames
        make_box(f"MSH_Win_{wid}_FrameTop", (0.16, bw + 0.14, 0.085), (-4.46, yc, 3.34), mats["wood_oak_warm"], grp_windows, export_col, bevel=0.007)
        make_box(f"MSH_Win_{wid}_FrameBot", (0.16, bw + 0.14, 0.065), (-4.46, yc, 0.78), mats["wood_oak_warm"], grp_windows, export_col, bevel=0.007)
        make_box(f"MSH_Win_{wid}_FrameL", (0.16, 0.085, bh), (-4.46, y0 + 0.03, zc), mats["wood_oak_warm"], grp_windows, export_col, bevel=0.007)
        make_box(f"MSH_Win_{wid}_FrameR", (0.16, 0.085, bh), (-4.46, y1 - 0.03, zc), mats["wood_oak_warm"], grp_windows, export_col, bevel=0.007)

        # Transom bar at Z = 2.68 + Center vertical casement stile + 2 casement mullions + transom muntins
        make_box(f"MSH_Win_{wid}_TransomBar", (0.12, bw - 0.06, 0.065), (-4.47, yc, 2.68), mats["wood_oak_warm"], grp_windows, export_col, bevel=0.005)
        make_box(f"MSH_Win_{wid}_CenterStile", (0.10, 0.070, bh - 0.10), (-4.47, yc, zc), mats["wood_oak_warm"], grp_windows, export_col, bevel=0.005)
        for m_idx, mz in enumerate((1.38, 2.03)):
            make_box(f"MSH_Win_{wid}_Mullion_{m_idx:02d}", (0.065, bw - 0.10, 0.038), (-4.47, yc, mz), mats["wood_oak_warm"], grp_windows, export_col, bevel=0.004)
        for sub_idx, sy_off in enumerate((-0.48, 0.48)):
            make_box(f"MSH_Win_{wid}_SubStile_{sub_idx:02d}", (0.055, 0.032, bh - 0.12), (-4.47, yc + sy_off, zc), mats["wood_oak_light"], grp_windows, export_col, bevel=0.003)

        # Brass espagnolette handles
        for h_idx, hy in enumerate((yc - 0.05, yc + 0.05)):
            make_box(f"MSH_Win_{wid}_Handle_{h_idx:02d}", (0.04, 0.018, 0.13), (-4.39, hy, 1.68), mats["brass"], grp_windows, export_col, bevel=0.004)

        # Sunlit warm glass pane (named SunlitGlass so Godot disables hard shadow blocking)
        make_box(
            f"MSH_Win_{wid}_SunlitGlass",
            (0.014, bw - 0.12, bh - 0.12),
            (-4.50, yc, zc),
            mats["window_glass"],
            grp_windows,
            export_col,
            bevel=0.001,
        )

        # Exterior Terracotta Flower Box + Sunlit Greenery & Coral Blossoms outside window!
        make_box(f"MSH_Win_{wid}_ExtPlanter", (0.28, bw - 0.16, 0.24), (-4.78, yc, 0.72), mats["terracotta_soft"], grp_windows, export_col, bevel=0.012)
        for bush_i in range(6):
            by_pos = y0 + 0.24 + bush_i * 0.30
            make_soft_cushion(
                f"MSH_Win_{wid}_ExtShrub_{bush_i:02d}",
                (0.24, 0.32, 0.22),
                (-4.78, by_pos, 0.90 + (bush_i % 2) * 0.04),
                mats["leaf_fresh"] if bush_i % 2 == 0 else mats["leaf_dark"],
                grp_windows,
                export_col,
                puff=0.20,
                subsurf=1,
            )
            if bush_i % 2 == 0:
                make_soft_cushion(
                    f"MSH_Win_{wid}_ExtBloom_{bush_i:02d}",
                    (0.09, 0.09, 0.08),
                    (-4.70, by_pos + 0.04, 1.02),
                    mats["blossom_peach"],
                    grp_windows,
                    export_col,
                    puff=0.22,
                    subsurf=1,
                )

    # Interior Window Sill Mini Succulents & Teacup
    make_cylinder("MSH_Sill_MiniPot_01", 0.065, 0.11, (-4.31, -1.92, 0.825), mats["pot_cream"], grp_windows, export_col, r_top=0.078)
    for sl_i in range(4):
        make_curved_leaf(
            f"MSH_Sill_MiniLeaf_{sl_i:02d}",
            0.14,
            0.065,
            0.03,
            (-4.31, -1.92, 0.87),
            (18.0, 0.0, sl_i * 90.0 + 25.0),
            mats["leaf_fresh"],
            grp_windows,
            export_col,
        )

    # Long Turned Walnut & Brass Curtain Rod spanning Y = -2.95 .. +2.55 at Z = 3.56
    make_capsule_tube(
        "MSH_Curtain_MainRod",
        (-4.20, -2.98, 3.56),
        (-4.20, 2.58, 3.56),
        0.020,
        0.020,
        mats["wood_walnut"],
        grp_windows,
        export_col,
    )
    for f_idx, fy in enumerate((-3.02, 2.62)):
        make_soft_cushion(f"MSH_Curtain_Finial_{f_idx:02d}", (0.065, 0.085, 0.065), (-4.20, fy, 3.56), mats["brass"], grp_windows, export_col, puff=0.22, subsurf=1)

    # Flowing Draped Sheer Curtains (named MSH_Curtain_* so Godot lets sunlight stream through!)
    curtain_specs = [
        ("Front", -2.68, 0.62, -1.0),
        ("CenterL", -0.36, 0.52, 0.7),
        ("CenterR", 0.04, 0.52, -0.7),
        ("Back", 2.28, 0.62, 1.0),
    ]
    for ctag, cy, cw, tie_dir in curtain_specs:
        make_draped_curtain(
            f"MSH_Curtain_Draped_{ctag}",
            cw,
            3.42,
            0.034,
            5,
            (-4.18, cy, 1.83),
            mats["curtain_sheer"],
            grp_windows,
            export_col,
            tie_side=tie_dir,
        )
        make_torus_ring(
            f"MSH_Curtain_TieRibbon_{ctag}",
            0.14,
            0.018,
            (-4.18, cy + tie_dir * 0.08, 1.28),
            mats["sage_green"],
            grp_windows,
            export_col,
            major_segs=28,
            minor_segs=10,
        )

    return grp_shell
