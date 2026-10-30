# -*- coding: utf-8 -*-
"""Stage 4 Module 2: High-Craft L-Shaped Artist/Dev Workstation, Pen Tablet, Dual Monitors & Plush Chair."""

from __future__ import annotations

import math
import bpy
from blender_core import (
    create_hierarchy_node,
    make_box,
    make_capsule_tube,
    make_cylinder,
    make_soft_cushion,
    make_torus_ring,
)


def build_workstation_zone(
    parent_zone_grp: bpy.types.Object,
    export_col: bpy.types.Collection,
    mats: dict[str, bpy.types.Material],
) -> bpy.types.Object:
    """
    Build L-shaped oak workstation in back-left loft corner:
    - Left wing along window wall: X in [-4.16, -3.28], Y in [+1.72, +3.72]
    - Back wing along back wall:   X in [-3.28, -1.18], Y in [+2.84, +3.72]
    - Desktop top surface at Z = 0.76m
    """
    zone = create_hierarchy_node("ZONE_Workstation", parent=parent_zone_grp, collection=export_col)
    cluster = create_hierarchy_node("CLUSTER_Workstation_Main", parent=zone, collection=export_col)

    # 1. Chamfered Honey-Oak L-Desktop + Under-Frame Aprons + 3-Drawer Cabinet + Wood-Slat PC
    grp_desk = create_hierarchy_node("GRP_Desk_Structure", parent=cluster, collection=export_col)
    make_box("MSH_Desk_Top_LeftWing", (0.88, 2.02, 0.048), (-3.72, 2.72, 0.736), mats["wood_oak_light"], grp_desk, export_col, bevel=0.016)
    make_box("MSH_Desk_Top_BackWing", (2.14, 0.88, 0.048), (-2.22, 3.28, 0.736), mats["wood_oak_light"], grp_desk, export_col, bevel=0.016)
    make_cylinder("MSH_Desk_CornerFillet", 0.36, 0.048, (-3.28, 2.84, 0.736), mats["wood_oak_light"], grp_desk, export_col, bevel=0.014)

    # 3-Drawer Pedestal with Brass Cup Pulls under front-left wing
    make_box("MSH_Desk_DrawerCarcass", (0.78, 0.54, 0.71), (-3.72, 2.02, 0.355), mats["wood_oak"], grp_desk, export_col, bevel=0.012)
    for d_idx, dz in enumerate((0.16, 0.37, 0.58)):
        make_box(f"MSH_Desk_DrawerFront_{d_idx:02d}", (0.028, 0.48, 0.185), (-3.32, 2.02, dz), mats["wood_oak_warm"], grp_desk, export_col, bevel=0.007)
        make_box(f"MSH_Desk_DrawerPull_{d_idx:02d}", (0.024, 0.12, 0.024), (-3.298, 2.02, dz + 0.02), mats["brass"], grp_desk, export_col, bevel=0.006)

    # Turned tapered oak desk legs
    leg_coords = [(-4.06, 3.60, "BL"), (-1.28, 3.60, "BR"), (-1.28, 2.94, "FR"), (-3.22, 3.60, "Mid")]
    for lx, ly, ltag in leg_coords:
        make_cylinder(f"MSH_Desk_Leg_{ltag}", 0.024, 0.712, (lx, ly, 0.356), mats["wood_walnut"], grp_desk, export_col, r_top=0.036)

    # Fractal-North style Wood-Slat + Charcoal SFF PC Tower under right wing
    make_box("MSH_PC_CaseBody", (0.23, 0.44, 0.46), (-1.52, 3.30, 0.23), mats["charcoal_metal"], grp_desk, export_col, bevel=0.010)
    for slat_i in range(6):
        sx = -1.60 + slat_i * 0.032
        make_box(f"MSH_PC_FrontWoodSlat_{slat_i:02d}", (0.018, 0.016, 0.42), (sx, 3.074, 0.23), mats["wood_walnut"], grp_desk, export_col, bevel=0.003)
    make_box("MSH_PC_PowerLED", (0.06, 0.010, 0.008), (-1.52, 3.072, 0.43), mats["screen_code_warm"], grp_desk, export_col, bevel=0.002)

    # 2. Articulated Dual Monitors + Pen Display Tablet + Mechanical Keyboard + Brass Banker's Lamp
    grp_tech = create_hierarchy_node("GRP_Desk_Monitors_And_Gear", parent=cluster, collection=export_col)

    monitors = [
        ("L", (-3.62, 2.92, 1.09), (0.0, 0.0, -54.0), 0.72, 0.41),
        ("R", (-2.76, 3.34, 1.09), (0.0, 0.0, -14.0), 0.76, 0.43),
    ]
    for mtag, mloc, mrot, mw, mh in monitors:
        piv_m = create_hierarchy_node(f"PIVOT_Monitor_{mtag}", parent=grp_tech, collection=export_col, location=mloc, display_type="ARROWS")
        rad = math.radians(mrot[2])
        back_x, back_y = -math.sin(rad) * 0.10, math.cos(rad) * 0.10
        make_cylinder(f"MSH_Monitor_{mtag}_Clamp", 0.048, 0.04, (mloc[0] + back_x, mloc[1] + back_y, 0.78), mats["charcoal_metal"], piv_m, export_col)
        make_capsule_tube(
            f"MSH_Monitor_{mtag}_Arm",
            (mloc[0] + back_x, mloc[1] + back_y, 0.79),
            (mloc[0] + back_x * 0.35, mloc[1] + back_y * 0.35, mloc[2]),
            0.020,
            0.016,
            mats["charcoal_metal"],
            piv_m,
            export_col,
        )
        make_box(f"MSH_Monitor_{mtag}_Frame", (mw, 0.028, mh), mloc, mats["charcoal_metal"], piv_m, export_col, bevel=0.008, rot_deg=mrot)
        fwd_x, fwd_y = math.sin(rad) * 0.015, -math.cos(rad) * 0.015
        make_box(f"MSH_Monitor_{mtag}_ScreenBG", (mw - 0.036, 0.006, mh - 0.036), (mloc[0] + fwd_x, mloc[1] + fwd_y, mloc[2]), mats["screen_dark_bg"], piv_m, export_col, bevel=0.002, rot_deg=mrot)

        right_x, right_y = math.cos(rad), math.sin(rad)
        for line_i in range(6):
            bar_w = 0.24 + (line_i % 3) * 0.10
            lx_off = -0.14 + (line_i % 2) * 0.05
            lz = mloc[2] + 0.13 - line_i * 0.050
            c_mat = mats["screen_code_green"] if line_i % 2 == 0 else mats["screen_code_warm"]
            make_box(
                f"MSH_Monitor_{mtag}_CodeLine_{line_i:02d}",
                (bar_w, 0.004, 0.016),
                (mloc[0] + fwd_x * 1.35 + right_x * lx_off, mloc[1] + fwd_y * 1.35 + right_y * lx_off, lz),
                c_mat,
                piv_m,
                export_col,
                bevel=0.001,
                rot_deg=mrot,
            )

    # Artist Pen Display Tablet + Stylus on right side of desk
    make_box("MSH_PenTablet_Body", (0.38, 0.25, 0.018), (-2.02, 3.16, 0.80), mats["charcoal_metal"], grp_tech, export_col, bevel=0.006, rot_deg=(18.0, 0.0, -8.0))
    make_box("MSH_PenTablet_Canvas", (0.32, 0.20, 0.006), (-2.02, 3.154, 0.808), mats["cushion_cream"], grp_tech, export_col, bevel=0.002, rot_deg=(18.0, 0.0, -8.0))
    make_capsule_tube("MSH_PenTablet_Stylus", (-1.78, 3.12, 0.77), (-1.75, 3.15, 0.90), 0.007, 0.005, mats["charcoal_metal"], grp_tech, export_col)

    # Sage Felt Desk Mat + Pastel Mechanical Keyboard + Mouse
    kb_rot = (0.0, 0.0, -34.0)
    make_box("MSH_Desk_FeltMat", (0.78, 0.34, 0.006), (-3.14, 2.82, 0.763), mats["sage_dark"], grp_tech, export_col, bevel=0.003, rot_deg=kb_rot)
    make_box("MSH_Keyboard_Case", (0.36, 0.14, 0.024), (-3.20, 2.85, 0.776), mats["cushion_cream"], grp_tech, export_col, bevel=0.006, rot_deg=kb_rot)

    rad_kb = math.radians(-34.0)
    rx, ry = math.cos(rad_kb), math.sin(rad_kb)
    fx, fy = -math.sin(rad_kb), math.cos(rad_kb)
    key_mats = [mats["wall_cream"], mats["sage_green"], mats["terracotta_soft"]]
    for kr in range(3):
        for kc in range(8):
            du = (kc - 3.5) * 0.039
            dv = (kr - 1.0) * 0.034
            kx = -3.20 + rx * du + fx * dv
            ky = 2.85 + ry * du + fy * dv
            km = key_mats[1] if (kr == 2 and kc in (0, 7)) else (key_mats[2] if (kr == 0 and kc == 0) else key_mats[0])
            make_box(f"MSH_Keycap_{kr}_{kc}", (0.031, 0.027, 0.012), (kx, ky, 0.793), km, grp_tech, export_col, bevel=0.002, rot_deg=kb_rot)

    make_soft_cushion("MSH_Desk_Mouse", (0.068, 0.11, 0.034), (-2.94, 2.69, 0.782), mats["cushion_cream"], grp_tech, export_col, rot_deg=kb_rot, puff=0.14)

    # Articulated Brass Studio Lamp with Warm Glowing Shade
    lamp_base = (-3.82, 2.12, 0.76)
    make_cylinder("MSH_DeskLamp_Base", 0.105, 0.026, (lamp_base[0], lamp_base[1], 0.773), mats["brass"], grp_tech, export_col)
    make_capsule_tube("MSH_DeskLamp_ArmLower", (lamp_base[0], lamp_base[1], 0.78), (-3.92, 2.18, 1.14), 0.012, 0.011, mats["brass"], grp_tech, export_col)
    make_capsule_tube("MSH_DeskLamp_ArmUpper", (-3.92, 2.18, 1.14), (-3.64, 2.34, 1.32), 0.011, 0.010, mats["brass"], grp_tech, export_col)
    make_cylinder("MSH_DeskLamp_Shade", 0.095, 0.15, (-3.59, 2.38, 1.27), mats["sage_dark"], grp_tech, export_col, r_top=0.042, rot_deg=(-26.0, 28.0, 0.0))
    make_cylinder("MSH_DeskLamp_WarmBulb", 0.042, 0.045, (-3.57, 2.40, 1.22), mats["bulb_warm_glow"], grp_tech, export_col)

    # Desk Books, Ceramic Coffee Cup + Handle + Saucer
    make_box("MSH_Desk_Book_01", (0.25, 0.19, 0.035), (-3.56, 2.38, 0.778), mats["book_ochre"], grp_tech, export_col, bevel=0.005, rot_deg=(0, 0, 14))
    make_box("MSH_Desk_Book_02", (0.22, 0.17, 0.030), (-3.56, 2.38, 0.810), mats["terracotta_soft"], grp_tech, export_col, bevel=0.005, rot_deg=(0, 0, -8))
    make_cylinder("MSH_Desk_Saucer", 0.072, 0.014, (-2.52, 2.98, 0.768), mats["pot_cream"], grp_tech, export_col, r_top=0.082)
    make_cylinder("MSH_Desk_CoffeeCup", 0.042, 0.078, (-2.52, 2.98, 0.812), mats["pot_cream"], grp_tech, export_col, r_top=0.048)
    make_torus_ring("MSH_Desk_CupHandle", 0.024, 0.006, (-2.47, 2.98, 0.812), mats["pot_cream"], grp_tech, export_col, major_segs=20, minor_segs=8, rot_deg=(90, 0, 0))

    # 3. Plush Subdivided Swivel Atelier Chair with Curved Wooden Shell & Armrests
    chair_pos = (-2.68, 2.32, 0.0)
    grp_chair_base = create_hierarchy_node("GRP_Chair_StaticBase", parent=cluster, collection=export_col, location=chair_pos)
    make_cylinder("MSH_Chair_GasLift", 0.028, 0.38, (chair_pos[0], chair_pos[1], 0.25), mats["charcoal_metal"], grp_chair_base, export_col)
    for leg_i in range(5):
        ang = leg_i * (2.0 * math.pi / 5.0)
        ex = chair_pos[0] + math.cos(ang) * 0.29
        ey = chair_pos[1] + math.sin(ang) * 0.29
        make_capsule_tube(f"MSH_Chair_StarLeg_{leg_i:02d}", (chair_pos[0], chair_pos[1], 0.095), (ex, ey, 0.055), 0.020, 0.015, mats["wood_walnut"], grp_chair_base, export_col)
        make_cylinder(f"MSH_Chair_Caster_{leg_i:02d}", 0.028, 0.030, (ex, ey, 0.028), mats["charcoal_metal"], grp_chair_base, export_col, rot_deg=(90, 0, 0))

    piv_chair = create_hierarchy_node("PIVOT_Chair_UpperSwivel", parent=cluster, collection=export_col, location=(chair_pos[0], chair_pos[1], 0.46), display_type="ARROWS")
    chair_rot = (0.0, 0.0, 144.0)
    rad_c = math.radians(chair_rot[2])
    make_soft_cushion("MSH_Chair_SeatCushion", (0.52, 0.50, 0.10), (chair_pos[0], chair_pos[1], 0.47), mats["sage_green"], piv_chair, export_col, rot_deg=chair_rot, puff=0.18)

    bx = chair_pos[0] - math.sin(rad_c) * 0.22
    by = chair_pos[1] + math.cos(rad_c) * 0.22
    make_soft_cushion("MSH_Chair_BackCushion", (0.48, 0.10, 0.52), (bx, by, 0.78), mats["sage_green"], piv_chair, export_col, rot_deg=chair_rot, puff=0.16)
    make_soft_cushion("MSH_Chair_LumbarPillow", (0.34, 0.08, 0.20), (chair_pos[0] - math.sin(rad_c) * 0.16, chair_pos[1] + math.cos(rad_c) * 0.16, 0.63), mats["cushion_cream"], piv_chair, export_col, rot_deg=chair_rot, puff=0.20)

    # Padded Armrests on left & right of swivel chair
    rx_c, ry_c = math.cos(rad_c), math.sin(rad_c)
    for arm_tag, side_s in (("L", -0.26), ("R", 0.26)):
        ax = chair_pos[0] + rx_c * side_s
        ay = chair_pos[1] + ry_c * side_s
        make_capsule_tube(f"MSH_Chair_ArmPost_{arm_tag}", (ax, ay, 0.47), (ax, ay, 0.65), 0.016, 0.014, mats["wood_walnut"], piv_chair, export_col)
        make_soft_cushion(f"MSH_Chair_ArmPad_{arm_tag}", (0.08, 0.28, 0.045), (ax, ay, 0.665), mats["wood_oak_light"], piv_chair, export_col, rot_deg=chair_rot, puff=0.12)

    return zone
