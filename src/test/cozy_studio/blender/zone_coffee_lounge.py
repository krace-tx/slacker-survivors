# -*- coding: utf-8 -*-
"""Stage 4 Module 4: Artisan Cafe Bar + Open Brass Hanging Rack, Plump Tufted L-Sofa, Braided Rug, Sculpted Cat & Botanical Plants."""

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
    make_torus_ring,
)


def _make_botanical_plant(
    prefix: str,
    loc: tuple[float, float, float],
    scale_f: float,
    leaf_count: int,
    with_stand: bool,
    parent: bpy.types.Object,
    export_col: bpy.types.Collection,
    mats: dict[str, bpy.types.Material],
) -> bpy.types.Object:
    """High-craft sculpted botanical plant (glazed ceramic planter + optional wood stand + arched pointed leaves)."""
    px, py, pz = loc
    grp = create_hierarchy_node(f"CLUSTER_Plant_{prefix}", parent=parent, collection=export_col, location=loc)

    stand_lift = 0.18 * scale_f if with_stand else 0.0
    if with_stand:
        for leg_i in range(4):
            ang = leg_i * (math.pi * 0.5) + math.pi * 0.25
            lx = px + math.cos(ang) * 0.17 * scale_f
            ly = py + math.sin(ang) * 0.17 * scale_f
            make_capsule_tube(
                f"MSH_Plant_{prefix}_StandLeg_{leg_i}",
                (lx, ly, pz + 0.01),
                (lx, ly, pz + 0.30 * scale_f),
                0.016 * scale_f,
                0.016 * scale_f,
                mats["wood_walnut"],
                grp,
                export_col,
            )
        make_torus_ring(
            f"MSH_Plant_{prefix}_StandRing",
            0.17 * scale_f,
            0.015 * scale_f,
            (px, py, pz + 0.16 * scale_f),
            mats["wood_walnut"],
            grp,
            export_col,
        )

    pot_h = 0.36 * scale_f
    pot_r = 0.20 * scale_f
    pot_z = pz + stand_lift
    make_cylinder(
        f"MSH_Plant_{prefix}_Pot",
        pot_r * 0.82,
        pot_h,
        (px, py, pot_z + pot_h * 0.5),
        mats["pot_cream"],
        grp,
        export_col,
        r_top=pot_r,
    )
    make_torus_ring(
        f"MSH_Plant_{prefix}_PotRim",
        pot_r,
        0.018 * scale_f,
        (px, py, pot_z + pot_h),
        mats["pot_cream"],
        grp,
        export_col,
    )
    make_cylinder(
        f"MSH_Plant_{prefix}_Soil",
        pot_r * 0.92,
        0.04 * scale_f,
        (px, py, pot_z + pot_h - 0.025 * scale_f),
        mats["wood_walnut"],
        grp,
        export_col,
    )

    for li in range(leaf_count):
        tier = li // 5
        ang = li * 2.39996 + 0.4  # Golden angle phyllotaxis for natural botanical arrangement!
        stem_h = pot_h + (0.20 + tier * 0.16 + (li % 3) * 0.06) * scale_f
        reach = (0.14 + (1 - tier * 0.25) * 0.16) * scale_f
        sx = px + math.cos(ang) * reach
        sy = py + math.sin(ang) * reach
        sz = pot_z + stem_h

        make_capsule_tube(
            f"MSH_Plant_{prefix}_Stem_{li:02d}",
            (px + math.cos(ang) * 0.03 * scale_f, py + math.sin(ang) * 0.03 * scale_f, pot_z + pot_h - 0.01),
            (sx, sy, sz),
            0.014 * scale_f,
            0.007 * scale_f,
            mats["leaf_dark"],
            grp,
            export_col,
        )

        yaw_deg = math.degrees(ang) - 90.0
        pitch_deg = 22.0 + (1 - min(1, tier)) * 18.0 + (li % 2) * 8.0
        leaf_len = (0.34 - tier * 0.04) * scale_f
        leaf_wid = (0.21 - tier * 0.02) * scale_f
        make_curved_leaf(
            f"MSH_Plant_{prefix}_Leaf_{li:02d}",
            leaf_len,
            leaf_wid,
            0.08 * scale_f,
            (sx, sy, sz),
            (pitch_deg, 0.0, yaw_deg),
            mats["leaf_fresh"] if li % 2 == 0 else mats["leaf_dark"],
            grp,
            export_col,
        )

    return grp


def build_coffee_lounge_zone(
    parent_zone_grp: bpy.types.Object,
    export_col: bpy.types.Collection,
    mats: dict[str, bpy.types.Material],
) -> bpy.types.Object:
    """Build Artisan Cafe Bar + Open Brass Rack, Tufted L-Sofa, Braided Rug, Sculpted Cat & Botanical Plants."""
    zone = create_hierarchy_node("ZONE_Coffee_Lounge", parent=parent_zone_grp, collection=export_col)

    # 1. Artisan Sage-Green Cafe Bar + Airy Open Walnut/Brass Suspended Rack (Back-Right)
    grp_bar = create_hierarchy_node("CLUSTER_Coffee_Bar", parent=zone, collection=export_col)
    cx, cy = 2.86, 2.58
    cw, cd, ch = 2.26, 0.68, 0.98

    make_box("MSH_CoffeeBar_Plinth", (cw - 0.06, cd - 0.06, 0.10), (cx, cy, 0.05), mats["wood_walnut"], grp_bar, export_col, bevel=0.008)
    make_box("MSH_CoffeeBar_Body", (cw, cd, ch - 0.10), (cx, cy, 0.54), mats["sage_green"], grp_bar, export_col, bevel=0.012)
    # Wainscot shaker panels + brass handles on front of cafe counter
    for p_idx, px_off in enumerate((-0.72, 0.0, 0.72)):
        make_box(f"MSH_CoffeeBar_ShakerPanel_{p_idx:02d}", (0.60, 0.024, 0.68), (cx + px_off, cy - cd * 0.5 - 0.006, 0.53), mats["sage_dark"], grp_bar, export_col, bevel=0.006)
        make_box(f"MSH_CoffeeBar_InnerTrim_{p_idx:02d}", (0.48, 0.016, 0.56), (cx + px_off, cy - cd * 0.5 - 0.014, 0.53), mats["sage_green"], grp_bar, export_col, bevel=0.005)
    # Thick Butcher-Block Honey-Oak Countertop
    make_box("MSH_CoffeeBar_ButcherTop", (cw + 0.10, cd + 0.10, 0.058), (cx, cy, ch + 0.029), mats["wood_oak_light"], grp_bar, export_col, bevel=0.014)

    # Open Walnut & Brass Suspended Cafe Shelf Rack (replaces boxy green block!)
    rack_z = 2.66
    for rx_off in (-0.96, 0.0, 0.96):
        for ry_off in (-0.22, 0.22):
            make_capsule_tube(
                f"MSH_CafeRack_Hanger_{rx_off:+.1f}_{ry_off:+.1f}",
                (cx + rx_off, cy + ry_off, rack_z),
                (cx + rx_off, cy + ry_off, 3.96),
                0.011,
                0.011,
                mats["brass"],
                grp_bar,
                export_col,
            )
    make_box("MSH_CafeRack_ShelfPlank", (cw - 0.08, 0.50, 0.036), (cx, cy, rack_z), mats["wood_walnut"], grp_bar, export_col, bevel=0.008)
    make_capsule_tube("MSH_CafeRack_GuardFront", (cx - 1.04, cy - 0.22, rack_z + 0.08), (cx + 1.04, cy - 0.22, rack_z + 0.08), 0.008, 0.008, mats["brass"], grp_bar, export_col)

    # Bottles, canisters & trailing leaves on suspended cafe rack
    for b_idx, bx_off in enumerate((-0.78, -0.58, -0.38, 0.36, 0.58)):
        make_cylinder(f"MSH_RackBottle_{b_idx:02d}", 0.044, 0.22 + (b_idx % 2) * 0.04, (cx + bx_off, cy, rack_z + 0.13), mats["book_ochre"] if b_idx % 2 == 0 else mats["pot_cream"], grp_bar, export_col, r_top=0.022)
    for rl_i in range(5):
        make_curved_leaf(
            f"MSH_RackVine_Leaf_{rl_i:02d}",
            0.18,
            0.10,
            0.07,
            (cx + 0.84, cy - 0.22, rack_z - rl_i * 0.11),
            (52.0, 0.0, 175.0 + rl_i * 12.0),
            mats["leaf_fresh"] if rl_i % 2 == 0 else mats["leaf_dark"],
            grp_bar,
            export_col,
        )

    # 3 Warm Ceramic Cone Pendant Lamps hanging below open rack
    for l_idx, lx_off in enumerate((-0.68, 0.0, 0.68)):
        lx = cx + lx_off
        make_capsule_tube(f"MSH_Pendant_{l_idx:02d}_Cord", (lx, cy, rack_z - 0.02), (lx, cy, 2.16), 0.006, 0.006, mats["charcoal_metal"], grp_bar, export_col)
        make_cylinder(f"MSH_Pendant_{l_idx:02d}_BrassCap", 0.032, 0.05, (lx, cy, 2.15), mats["brass"], grp_bar, export_col)
        make_cylinder(f"MSH_Pendant_{l_idx:02d}_Shade", 0.155, 0.18, (lx, cy, 2.05), mats["pot_cream"], grp_bar, export_col, r_top=0.045)
        make_torus_ring(f"MSH_Pendant_{l_idx:02d}_BrassRim", 0.155, 0.008, (lx, cy, 1.96), mats["brass"], grp_bar, export_col, major_segs=32, minor_segs=8)
        make_soft_cushion(f"MSH_Pendant_{l_idx:02d}_WarmBulb", (0.09, 0.09, 0.09), (lx, cy, 1.97), mats["bulb_warm_glow"], grp_bar, export_col, puff=0.25, subsurf=1)

    # Back Wall Cafe Menu Chalkboard + Wall Mug Shelf (Y = +3.85)
    make_box("MSH_MenuBoard_Frame", (1.52, 0.040, 0.92), (2.86, 3.86, 2.26), mats["wood_walnut"], grp_bar, export_col, bevel=0.009)
    make_box("MSH_MenuBoard_Slate", (1.38, 0.016, 0.78), (2.86, 3.840, 2.26), mats["charcoal_metal"], grp_bar, export_col, bevel=0.002)
    for mline in range(5):
        make_box(f"MSH_MenuBoard_Chalk_{mline:02d}", (0.52 - (mline % 3) * 0.11, 0.006, 0.018), (2.56, 3.828, 2.48 - mline * 0.11), mats["wall_cream"], grp_bar, export_col, bevel=0.001)

    # Retro 2-Group Espresso Machine + Grinder + Pastry Cloche Dome on Butcher Countertop (Z = 1.038)
    ct_z = ch + 0.058
    ex_x = cx + 0.64
    make_box("MSH_Espresso_Body", (0.48, 0.36, 0.40), (ex_x, cy + 0.05, ct_z + 0.20), mats["sage_dark"], grp_bar, export_col, bevel=0.018)
    make_box("MSH_Espresso_BrassTop", (0.50, 0.38, 0.036), (ex_x, cy + 0.05, ct_z + 0.415), mats["brass"], grp_bar, export_col, bevel=0.008)
    make_cylinder("MSH_Espresso_Gauge", 0.038, 0.018, (ex_x, cy - 0.132, ct_z + 0.31), mats["cushion_cream"], grp_bar, export_col, rot_deg=(90, 0, 0))
    for gh_i, gx_off in enumerate((-0.11, 0.11)):
        make_cylinder(f"MSH_Espresso_Group_{gh_i}", 0.042, 0.05, (ex_x + gx_off, cy - 0.12, ct_z + 0.23), mats["brass"], grp_bar, export_col)
        make_capsule_tube(f"MSH_Espresso_Portafilter_{gh_i}", (ex_x + gx_off, cy - 0.13, ct_z + 0.21), (ex_x + gx_off - 0.04, cy - 0.26, ct_z + 0.19), 0.012, 0.015, mats["wood_walnut"], grp_bar, export_col)

    # Coffee Grinder + Bean Hopper
    make_cylinder("MSH_CoffeeGrinder_Base", 0.085, 0.24, (cx + 0.16, cy + 0.06, ct_z + 0.12), mats["charcoal_metal"], grp_bar, export_col)
    make_cylinder("MSH_CoffeeGrinder_Hopper", 0.065, 0.15, (cx + 0.16, cy + 0.06, ct_z + 0.31), mats["iced_latte"], grp_bar, export_col, r_top=0.095)

    # Pastry Wooden Platter + Croissant + Glass Cloche
    make_cylinder("MSH_Pastry_Board", 0.16, 0.022, (cx - 0.46, cy - 0.04, ct_z + 0.011), mats["wood_walnut"], grp_bar, export_col)
    make_soft_cushion("MSH_Pastry_Croissant", (0.13, 0.08, 0.065), (cx - 0.46, cy - 0.04, ct_z + 0.05), mats["cat_ginger"], grp_bar, export_col, rot_deg=(0, 0, 28), puff=0.22)
    make_soft_cushion("MSH_Pastry_GlassCloche", (0.28, 0.28, 0.22), (cx - 0.46, cy - 0.04, ct_z + 0.12), mats["window_glass"], grp_bar, export_col, puff=0.24, subsurf=1)
    for cup_i in range(3):
        make_cylinder(f"MSH_Bar_CupStack_{cup_i}", 0.044, 0.075, (cx - 0.84 + cup_i * 0.11, cy + 0.06, ct_z + 0.038), mats["pot_cream"], grp_bar, export_col, r_top=0.050)

    # 2. Plump Subdivided Tufted L-Sofa + Waffle Throw Blanket + Oval Coffee Table (Front-Right)
    grp_lounge = create_hierarchy_node("CLUSTER_Sofa_And_Table", parent=zone, collection=export_col)
    sx_c, sy_c = 3.18, -1.05

    # Turned Walnut Sofa Legs + Solid Oak Frame
    make_box("MSH_Sofa_OakFrame", (0.94, 2.86, 0.13), (sx_c, sy_c, 0.135), mats["wood_oak"], grp_lounge, export_col, bevel=0.012)
    make_box("MSH_Sofa_ChaiseFrame", (0.86, 0.94, 0.13), (sx_c - 0.88, sy_c + 0.96, 0.135), mats["wood_oak"], grp_lounge, export_col, bevel=0.012)
    for sl_x, sl_y in ((sx_c - 0.38, sy_c - 1.32), (sx_c + 0.38, sy_c - 1.32), (sx_c + 0.38, sy_c + 1.32), (sx_c - 1.22, sy_c + 1.32), (sx_c - 1.22, sy_c + 0.56)):
        make_cylinder(f"MSH_Sofa_Leg_{sl_x:.1f}_{sl_y:.1f}", 0.022, 0.09, (sl_x, sl_y, 0.045), mats["wood_walnut"], grp_lounge, export_col, r_top=0.035)

    # Plump Rounded Backrest & Rolled Armrests
    make_soft_cushion("MSH_Sofa_BackShell", (0.26, 2.90, 0.72), (sx_c + 0.36, sy_c, 0.54), mats["sage_green"], grp_lounge, export_col, puff=0.14)
    make_soft_cushion("MSH_Sofa_ArmFront", (0.94, 0.24, 0.54), (sx_c, sy_c - 1.36, 0.44), mats["sage_green"], grp_lounge, export_col, puff=0.15)
    make_soft_cushion("MSH_Sofa_ArmBack", (0.94, 0.24, 0.54), (sx_c, sy_c + 1.36, 0.44), mats["sage_green"], grp_lounge, export_col, puff=0.15)

    # 3 Deep Seat Cushions + Chaise Cushion + Back Cushions
    for sc_i, sy_off in enumerate((-0.88, 0.0, 0.88)):
        make_soft_cushion(f"MSH_Sofa_SeatCushion_{sc_i:02d}", (0.74, 0.86, 0.22), (sx_c - 0.08, sy_c + sy_off, 0.29), mats["cushion_cream"], grp_lounge, export_col, puff=0.17)
        make_soft_cushion(f"MSH_Sofa_BackPillow_{sc_i:02d}", (0.22, 0.80, 0.44), (sx_c + 0.16, sy_c + sy_off, 0.58), mats["sage_green"] if sc_i != 1 else mats["cushion_cream"], grp_lounge, export_col, rot_deg=(0, -10, 0), puff=0.18)

    make_soft_cushion("MSH_Sofa_ChaiseCushion", (0.88, 0.88, 0.22), (sx_c - 0.88, sy_c + 0.92, 0.29), mats["cushion_cream"], grp_lounge, export_col, puff=0.17)
    # Cozy Ochre & Peach Accent Throw Pillows + Draped Blanket
    make_soft_cushion("MSH_Sofa_AccentPillow_01", (0.16, 0.42, 0.40), (sx_c + 0.04, sy_c - 1.02, 0.57), mats["book_ochre"], grp_lounge, export_col, rot_deg=(12, -16, 18), puff=0.20)
    make_soft_cushion("MSH_Sofa_AccentPillow_02", (0.16, 0.40, 0.38), (sx_c + 0.04, sy_c + 0.98, 0.57), mats["blossom_peach"], grp_lounge, export_col, rot_deg=(-10, -15, -16), puff=0.20)
    make_soft_cushion("MSH_Sofa_ThrowBlanket", (0.52, 0.92, 0.08), (sx_c - 1.02, sy_c + 0.92, 0.38), mats["rug_oat_warm"], grp_lounge, export_col, rot_deg=(0, 8, 0), puff=0.12)

    # Oval Mid-Century Oak Coffee Table + Wooden Tray + Pour-Over Carafe & Artbook
    tx, ty = 1.62, -1.58
    make_soft_cushion("MSH_CoffeeTable_OvalTop", (0.76, 1.24, 0.048), (tx, ty, 0.40), mats["wood_oak_light"], grp_lounge, export_col, puff=0.06, subsurf=2)
    for lx_o, ly_o in ((-0.24, -0.44), (0.24, -0.44), (-0.24, 0.44), (0.24, 0.44)):
        make_capsule_tube(
            f"MSH_CoffeeTable_Leg_{lx_o:+.2f}_{ly_o:+.2f}",
            (tx + lx_o * 1.15, ty + ly_o * 1.08, 0.01),
            (tx + lx_o, ty + ly_o, 0.39),
            0.020,
            0.026,
            mats["wood_walnut"],
            grp_lounge,
            export_col,
        )
    make_cylinder("MSH_Table_WoodTray", 0.21, 0.024, (tx - 0.04, ty - 0.18, 0.432), mats["wood_walnut"], grp_lounge, export_col)
    make_cylinder("MSH_Table_Carafe", 0.068, 0.14, (tx - 0.06, ty - 0.22, 0.51), mats["iced_latte"], grp_lounge, export_col, r_top=0.036)
    make_cylinder("MSH_Table_TeaCup", 0.042, 0.065, (tx + 0.05, ty - 0.11, 0.472), mats["pot_cream"], grp_lounge, export_col, r_top=0.048)
    make_box("MSH_Table_OpenBook", (0.28, 0.36, 0.032), (tx + 0.06, ty + 0.24, 0.436), mats["sage_green"], grp_lounge, export_col, bevel=0.005, rot_deg=(0, 0, -18))

    # 3. Large Concentric Braided Wool Area Rug with Torus Coils (Center X = -0.42, Y = -0.55)
    grp_rug = create_hierarchy_node("CLUSTER_Center_WovenRug", parent=zone, collection=export_col)
    rx, ry = -0.42, -0.55
    make_cylinder("MSH_Rug_BaseDisc", 1.72, 0.016, (rx, ry, 0.008), mats["rug_oat"], grp_rug, export_col, segs=64, bevel=0.006)
    make_cylinder("MSH_Rug_InnerDisc", 1.18, 0.018, (rx, ry, 0.0095), mats["cushion_cream"], grp_rug, export_col, segs=64, bevel=0.005)
    make_cylinder("MSH_Rug_CoreDisc", 0.62, 0.020, (rx, ry, 0.0105), mats["rug_oat_warm"], grp_rug, export_col, segs=48, bevel=0.005)
    for coil_i, r_maj in enumerate((0.62, 1.18, 1.70)):
        make_torus_ring(
            f"MSH_Rug_BraidedRim_{coil_i:02d}",
            r_maj,
            0.014,
            (rx, ry, 0.013),
            mats["rug_oat_warm"] if coil_i % 2 == 0 else mats["cushion_cream"],
            grp_rug,
            export_col,
            major_segs=64,
            minor_segs=10,
        )

    # 4. Sunlit Knitted Pouf + Sculpted Plump Sleeping Ginger Cat + Rattan Basket (X = -3.08, Y = -1.05)
    grp_cat = create_hierarchy_node("CLUSTER_Pouf_And_SleepingCat", parent=zone, collection=export_col)
    px, py = -3.08, -1.05
    make_soft_cushion("MSH_Pouf_KnittedCushion", (0.86, 0.86, 0.30), (px, py, 0.165), mats["rug_oat_warm"], grp_cat, export_col, puff=0.20)
    for rib_i in range(3):
        make_torus_ring(f"MSH_Pouf_KnitBand_{rib_i}", 0.42 - rib_i * 0.03, 0.016, (px, py, 0.10 + rib_i * 0.07), mats["cushion_cream"], grp_cat, export_col, major_segs=36, minor_segs=8)

    # Sculpted Sleeping Ginger Cat on Pouf (Z ~ 0.36)
    make_soft_cushion("MSH_Cat_PlumpBody", (0.38, 0.31, 0.17), (px + 0.03, py + 0.03, 0.375), mats["cat_ginger"], grp_cat, export_col, rot_deg=(0, 0, 24), puff=0.24)
    make_soft_cushion("MSH_Cat_RoundHead", (0.19, 0.18, 0.16), (px - 0.12, py - 0.05, 0.40), mats["cat_ginger"], grp_cat, export_col, rot_deg=(8, -6, -22), puff=0.25)
    make_soft_cushion("MSH_Cat_CheekPatch", (0.12, 0.10, 0.08), (px - 0.15, py - 0.08, 0.375), mats["cushion_cream"], grp_cat, export_col, puff=0.22)
    for paw_i, p_off in enumerate(((-0.18, 0.02), (-0.09, -0.14))):
        make_soft_cushion(f"MSH_Cat_TuckedPaw_{paw_i}", (0.075, 0.065, 0.048), (px + p_off[0], py + p_off[1], 0.335), mats["cushion_cream"], grp_cat, export_col, puff=0.22)
    for ear_i, (ex_o, ey_o, erot) in enumerate(((-0.17, -0.09, -18.0), (-0.08, -0.11, 16.0))):
        make_cylinder(f"MSH_Cat_Ear_{ear_i}", 0.034, 0.068, (px + ex_o, py + ey_o, 0.485), mats["cat_ginger"], grp_cat, export_col, segs=16, r_top=0.005, rot_deg=(10.0, erot, 0.0))
    make_soft_cushion("MSH_Cat_CollarBell", (0.032, 0.032, 0.032), (px - 0.14, py - 0.12, 0.345), mats["brass"], grp_cat, export_col, puff=0.25, subsurf=1)
    make_capsule_tube("MSH_Cat_TailSeg1", (px + 0.18, py + 0.09, 0.35), (px + 0.14, py - 0.12, 0.345), 0.032, 0.026, mats["cat_ginger"], grp_cat, export_col)
    make_capsule_tube("MSH_Cat_TailSeg2", (px + 0.14, py - 0.12, 0.345), (px - 0.02, py - 0.16, 0.34), 0.026, 0.020, mats["cushion_cream"], grp_cat, export_col)

    # Woven Blanket Basket beside Window
    make_cylinder("MSH_Window_BlanketBasket", 0.22, 0.34, (-3.86, -0.18, 0.17), mats["rug_oat_warm"], grp_cat, export_col, r_top=0.26)
    make_soft_cushion("MSH_Basket_RolledThrow", (0.22, 0.30, 0.18), (-3.86, -0.18, 0.36), mats["sage_green"], grp_cat, export_col, rot_deg=(16, 0, 25), puff=0.18)

    # 5. Four Lush Sculpted Botanical Plants with Curved Pointed Leaves & Ceramic Planters
    _make_botanical_plant("WindowFront_Monstera", (-3.82, -2.55, 0.0), 1.25, 11, True, zone, export_col, mats)
    _make_botanical_plant("WindowFront_MiniFicus", (-3.76, -3.28, 0.0), 0.76, 8, False, zone, export_col, mats)
    _make_botanical_plant("DeskWindow_FiddleFig", (-3.78, 1.15, 0.0), 1.02, 10, True, zone, export_col, mats)
    _make_botanical_plant("SofaCorner_Palm", (3.65, -2.85, 0.0), 0.96, 9, False, zone, export_col, mats)

    return zone
