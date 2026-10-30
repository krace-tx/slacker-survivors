# -*- coding: utf-8 -*-
"""Stage 4 Module 3: Grand 3.18m Dual-Bay Archival Bookcase, Library Ladder & Cozy Wall Art Gallery."""

from __future__ import annotations

import math
import bpy
from blender_core import (
    create_hierarchy_node,
    make_box,
    make_capsule_tube,
    make_curved_leaf,
    make_cylinder,
    make_soft_cushion,
)


def build_bookshelf_decor_zone(
    parent_zone_grp: bpy.types.Object,
    export_col: bpy.types.Collection,
    mats: dict[str, bpy.types.Material],
) -> bpy.types.Object:
    """Build grand 3.18m archival oak bookcase with brass ladder + rich wall gallery."""
    zone = create_hierarchy_node("ZONE_Bookshelf_Decor", parent=parent_zone_grp, collection=export_col)
    grp_case = create_hierarchy_node("CLUSTER_Grand_Bookcase", parent=zone, collection=export_col)
    grp_wall_art = create_hierarchy_node("CLUSTER_Wall_Gallery", parent=zone, collection=export_col)

    # 1. Grand Dual-Bay Archival Oak Bookcase at X = +0.22, Y = +3.62, Z = 0.0 .. 3.18m
    bx, by = 0.22, 3.62
    bw, bd, bh = 1.92, 0.44, 3.18

    # Plinth base + Crown cornice + Back panel + Left/Center/Right stiles
    make_box("MSH_Bookcase_Plinth", (bw + 0.04, bd + 0.04, 0.11), (bx, by, 0.055), mats["wood_walnut"], grp_case, export_col, bevel=0.008)
    make_box("MSH_Bookcase_CrownCornice", (bw + 0.12, bd + 0.10, 0.11), (bx, by - 0.02, bh + 0.03), mats["wood_walnut"], grp_case, export_col, bevel=0.012)
    make_box("MSH_Bookcase_BackPanel", (bw - 0.04, 0.024, bh - 0.10), (bx, by + bd * 0.5 - 0.015, bh * 0.5 + 0.04), mats["wood_oak"], grp_case, export_col, bevel=0.004)

    for st_tag, sx_off in (("Left", -bw * 0.5 + 0.025), ("Center", 0.0), ("Right", bw * 0.5 - 0.025)):
        make_box(f"MSH_Bookcase_Upright_{st_tag}", (0.050, bd, bh), (bx + sx_off, by, bh * 0.5), mats["wood_oak_warm"], grp_case, export_col, bevel=0.008)

    # Lower closed cabinet doors (Z = 0.11 .. 0.74) with recessed panels & brass knobs
    make_box("MSH_Bookcase_CounterShelf", (bw + 0.03, bd + 0.03, 0.042), (bx, by - 0.01, 0.76), mats["wood_walnut"], grp_case, export_col, bevel=0.008)
    for d_idx, dx_off in enumerate((-0.70, -0.24, 0.24, 0.70)):
        make_box(f"MSH_Bookcase_Door_{d_idx:02d}", (0.42, 0.024, 0.60), (bx + dx_off, by - bd * 0.5 + 0.01, 0.43), mats["wood_oak_light"], grp_case, export_col, bevel=0.006)
        knob_x = bx + dx_off + (0.15 if d_idx % 2 == 0 else -0.15)
        make_soft_cushion(f"MSH_Bookcase_Knob_{d_idx:02d}", (0.026, 0.028, 0.026), (knob_x, by - bd * 0.5 - 0.012, 0.52), mats["brass"], grp_case, export_col, puff=0.22, subsurf=1)

    # 5 Upper open bookshelf tiers (Z = 1.24, 1.72, 2.20, 2.68, 3.14)
    shelf_zs = [1.24, 1.72, 2.20, 2.68, 3.14]
    for s_idx, sz in enumerate(shelf_zs):
        make_box(f"MSH_Bookcase_Shelf_{s_idx:02d}", (bw - 0.04, bd - 0.02, 0.036), (bx, by - 0.005, sz), mats["wood_oak_light"], grp_case, export_col, bevel=0.006)

    # Populate both bays with 48 varied pastel books, horizontal stacks, globe & trailing ivy!
    book_palette = [
        mats["sage_green"],
        mats["terracotta_soft"],
        mats["book_ochre"],
        mats["book_navy"],
        mats["cushion_cream"],
        mats["sage_dark"],
        mats["blossom_peach"],
    ]
    tier_bases = [0.781, 1.258, 1.738, 2.218, 2.698]
    for t_idx, bz in enumerate(tier_bases):
        for bay_idx, bay_x0 in enumerate((bx - 0.88, bx + 0.05)):
            cur_x = bay_x0
            bay_end = bay_x0 + 0.78
            b_i = 0
            while cur_x < bay_end:
                # Leave curated display nooks for globe / camera / storage baskets
                if t_idx == 1 and bay_idx == 1 and cur_x > bay_x0 + 0.34:
                    break
                if t_idx == 3 and bay_idx == 0 and cur_x > bay_x0 + 0.42:
                    break
                thick = 0.032 + ((b_i + t_idx + bay_idx) % 4) * 0.009
                bh_book = 0.27 + ((b_i * 3 + t_idx) % 4) * 0.034
                bd_book = 0.24 + (b_i % 2) * 0.025
                bmat = book_palette[(b_i + t_idx * 2 + bay_idx * 3) % len(book_palette)]
                tilt = -7.0 if (b_i == 6 and cur_x + 0.08 < bay_end) else 0.0
                make_box(
                    f"MSH_Book_T{t_idx}_B{bay_idx}_{b_i:02d}",
                    (thick, bd_book, bh_book),
                    (cur_x + thick * 0.5, by - 0.02, bz + bh_book * 0.5),
                    bmat,
                    grp_case,
                    export_col,
                    bevel=0.004,
                    rot_deg=(0.0, tilt, 0.0),
                )
                cur_x += thick + (0.022 if abs(tilt) > 1.0 else 0.005)
                b_i += 1

    # Vintage Brass & Sage Globe in Tier 1 Bay 1 nook + Woven Basket in Tier 3 Bay 0
    gx, gy, gz = bx + 0.62, by - 0.03, 1.258
    make_cylinder("MSH_Prop_GlobeBase", 0.075, 0.022, (gx, gy, gz + 0.011), mats["wood_walnut"], grp_case, export_col)
    make_capsule_tube("MSH_Prop_GlobeStem", (gx, gy, gz + 0.02), (gx, gy, gz + 0.26), 0.010, 0.010, mats["brass"], grp_case, export_col)
    make_soft_cushion("MSH_Prop_GlobeSphere", (0.21, 0.21, 0.21), (gx, gy, gz + 0.18), mats["sage_green"], grp_case, export_col, rot_deg=(0, 23.5, 0), puff=0.26)
    make_box("MSH_Prop_NookBasket", (0.30, 0.28, 0.22), (bx - 0.26, by - 0.03, 2.218 + 0.11), mats["rug_oat_warm"], grp_case, export_col, bevel=0.012)

    # Trailing Pothos Ivy Plant cascading down top-left corner of grand bookcase
    ivy_x, ivy_y, ivy_z = bx - 0.72, by - 0.04, 3.24
    make_cylinder("MSH_Bookcase_IvyPot", 0.10, 0.16, (ivy_x, ivy_y, ivy_z + 0.08), mats["terracotta_soft"], grp_case, export_col, r_top=0.12)
    for v_idx in range(7):
        drop_z = ivy_z + 0.04 - v_idx * 0.13
        vy = ivy_y - 0.16 - (v_idx % 2) * 0.02
        vx = ivy_x - 0.06 + math.sin(v_idx * 1.1) * 0.06
        make_curved_leaf(
            f"MSH_Bookcase_IvyLeaf_{v_idx:02d}",
            0.16,
            0.10,
            0.06,
            (vx, vy, drop_z),
            (55.0, 0.0, 180.0 + math.sin(v_idx) * 25.0),
            mats["leaf_fresh"] if v_idx % 2 == 0 else mats["leaf_dark"],
            grp_case,
            export_col,
        )

    # Brass Sliding Rail + Leaning Wooden Library Ladder on right half of bookcase
    make_capsule_tube("MSH_Ladder_BrassRail", (bx - 0.94, by - 0.25, 2.74), (bx + 0.94, by - 0.25, 2.74), 0.014, 0.014, mats["brass"], grp_case, export_col)
    lad_x = bx + 0.72
    for side_i, lx_off in enumerate((-0.17, 0.17)):
        make_capsule_tube(
            f"MSH_Ladder_Stile_{side_i}",
            (lad_x + lx_off, by - 0.74, 0.02),
            (lad_x + lx_off, by - 0.25, 2.76),
            0.018,
            0.016,
            mats["wood_walnut"],
            grp_case,
            export_col,
        )
    for rung_i in range(7):
        t = (rung_i + 1) / 8.0
        ry = (by - 0.74) * (1.0 - t) + (by - 0.25) * t
        rz = 0.02 * (1.0 - t) + 2.76 * t
        make_capsule_tube(f"MSH_Ladder_Rung_{rung_i:02d}", (lad_x - 0.17, ry, rz), (lad_x + 0.17, ry, rz), 0.012, 0.012, mats["wood_oak_warm"], grp_case, export_col)

    # 2. Cozy Wall Art Gallery, Pinboard & Analog Wall Clock above Workstation (X = -2.15, Y = +3.86)
    # Cork Pinboard with Pastel Notes
    make_box("MSH_Corkboard_Frame", (0.96, 0.036, 0.64), (-2.12, 3.86, 2.18), mats["wood_oak_warm"], grp_wall_art, export_col, bevel=0.008)
    make_box("MSH_Corkboard_Surface", (0.88, 0.016, 0.56), (-2.12, 3.842, 2.18), mats["rug_oat_warm"], grp_wall_art, export_col, bevel=0.002)
    note_specs = [
        (-2.36, 2.30, 0.16, 0.19, -6.0, mats["cushion_cream"]),
        (-2.14, 2.26, 0.15, 0.15, 5.0, mats["blossom_peach"]),
        (-1.88, 2.31, 0.17, 0.20, -4.0, mats["sage_green"]),
        (-2.26, 2.04, 0.18, 0.14, 8.0, mats["book_ochre"]),
        (-1.96, 2.05, 0.15, 0.16, -7.0, mats["wall_cream"]),
    ]
    for n_i, (nx, nz, nw, nh, nrot, nmat) in enumerate(note_specs):
        make_box(f"MSH_PinNote_{n_i:02d}", (nw, 0.008, nh), (nx, 3.830, nz), nmat, grp_wall_art, export_col, bevel=0.002, rot_deg=(0.0, nrot, 0.0))

    # Analog Round Wooden Wall Clock at (-2.12, 3.85, 2.98)
    make_cylinder("MSH_WallClock_Rim", 0.22, 0.045, (-2.12, 3.855, 2.98), mats["wood_walnut"], grp_wall_art, export_col, rot_deg=(90.0, 0.0, 0.0))
    make_cylinder("MSH_WallClock_Face", 0.185, 0.016, (-2.12, 3.835, 2.98), mats["cushion_cream"], grp_wall_art, export_col, rot_deg=(90.0, 0.0, 0.0))
    make_box("MSH_WallClock_HandHour", (0.10, 0.008, 0.014), (-2.07, 3.822, 2.98), mats["charcoal_metal"], grp_wall_art, export_col, bevel=0.002)
    make_box("MSH_WallClock_HandMin", (0.012, 0.008, 0.13), (-2.12, 3.820, 3.04), mats["charcoal_metal"], grp_wall_art, export_col, bevel=0.002)

    # Two Floating Corner Oak Shelves on Left/Back corner + Framed Botanical Prints
    make_box("MSH_WallShelf_Left_Top", (0.24, 1.08, 0.038), (-4.26, 3.12, 2.42), mats["wood_oak_warm"], grp_wall_art, export_col, bevel=0.007)
    make_box("MSH_WallShelf_Left_Bot", (0.24, 1.08, 0.038), (-4.26, 3.12, 1.94), mats["wood_oak_warm"], grp_wall_art, export_col, bevel=0.007)
    for sb_i in range(7):
        make_box(
            f"MSH_WallShelf_Book_{sb_i:02d}",
            (0.17, 0.034, 0.23 + (sb_i % 3) * 0.025),
            (-4.26, 2.74 + sb_i * 0.044, 2.08),
            book_palette[sb_i % len(book_palette)],
            grp_wall_art,
            export_col,
            bevel=0.004,
        )
    make_box("MSH_FramedArt_LeftWall_Border", (0.032, 0.46, 0.58), (-4.37, 3.22, 2.92), mats["wood_walnut"], grp_wall_art, export_col, bevel=0.006)
    make_box("MSH_FramedArt_LeftWall_Canvas", (0.014, 0.38, 0.50), (-4.354, 3.22, 2.92), mats["blossom_peach"], grp_wall_art, export_col, bevel=0.002)

    return zone
