# -*- coding: utf-8 -*-
"""Master Builder for High-Craft Cozy Anime Atelier Venue (`mdl_cozy_studio_room.glb`)."""

from __future__ import annotations

import os
import sys
import bpy

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
if SCRIPT_DIR not in sys.path:
    sys.path.insert(0, SCRIPT_DIR)

from blender_core import (  # noqa: E402
    clear_scene,
    create_asset_collection_tree,
    create_hierarchy_node,
    create_pbr_mat,
)
from zone_shell import build_building_shell  # noqa: E402
from zone_workstation import build_workstation_zone  # noqa: E402
from zone_bookshelf_decor import build_bookshelf_decor_zone  # noqa: E402
from zone_coffee_lounge import build_coffee_lounge_zone  # noqa: E402


def build_palette_materials() -> dict[str, bpy.types.Material]:
    """Curated warm Makoto-Shinkai / Ghibli pastel anime atelier color palette."""
    return {
        "wall_cream": create_pbr_mat("Mat_Wall_Cream", "#FCF3E4", roughness=0.80),
        "wood_oak": create_pbr_mat("Mat_Wood_Oak", "#D4985F", roughness=0.55),
        "wood_oak_light": create_pbr_mat("Mat_Wood_OakLight", "#E2AE78", roughness=0.52),
        "wood_oak_warm": create_pbr_mat("Mat_Wood_OakWarm", "#C5864D", roughness=0.56),
        "wood_walnut": create_pbr_mat("Mat_Wood_WalnutTrim", "#8E5730", roughness=0.52),
        "sage_green": create_pbr_mat("Mat_Sage_Green", "#9AB493", roughness=0.68),
        "sage_dark": create_pbr_mat("Mat_Sage_Dark", "#6F8B6B", roughness=0.72),
        "cushion_cream": create_pbr_mat("Mat_Cushion_Cream", "#FDF7EC", roughness=0.80),
        "rug_oat": create_pbr_mat("Mat_Rug_Oat", "#F1E4CD", roughness=0.84),
        "rug_oat_warm": create_pbr_mat("Mat_Rug_OatWarm", "#E4CEAA", roughness=0.82),
        "pot_cream": create_pbr_mat("Mat_Ceramic_Cream", "#F7EFE3", roughness=0.38),
        "brass": create_pbr_mat("Mat_Warm_Brass", "#E5B254", roughness=0.32, metallic=0.65),
        "charcoal_metal": create_pbr_mat("Mat_Charcoal_Slate", "#3C3836", roughness=0.48, metallic=0.20),
        "leaf_fresh": create_pbr_mat("Mat_Leaf_Fresh", "#6DA85B", roughness=0.58),
        "leaf_dark": create_pbr_mat("Mat_Leaf_Dark", "#4E8242", roughness=0.62),
        "cat_ginger": create_pbr_mat("Mat_Cat_Ginger", "#EC994C", roughness=0.76),
        "terracotta_soft": create_pbr_mat("Mat_Terracotta_Soft", "#DF896A", roughness=0.68),
        "blossom_peach": create_pbr_mat("Mat_Blossom_Peach", "#F4B49E", roughness=0.70),
        "book_ochre": create_pbr_mat("Mat_Book_Ochre", "#E3B363", roughness=0.65),
        "book_navy": create_pbr_mat("Mat_Book_SlateBlue", "#7088A2", roughness=0.65),
        "iced_latte": create_pbr_mat("Mat_Iced_Latte", "#BA7E4E", roughness=0.22, alpha=0.88),
        "curtain_sheer": create_pbr_mat(
            "Mat_Curtain_Sheer",
            "#FFFDF9",
            roughness=0.72,
            emission_hex="#FFF5DF",
            emission_strength=0.18,
            alpha=0.80,
        ),
        "window_glass": create_pbr_mat(
            "Mat_Window_SunlitGlass",
            "#FFF8E2",
            roughness=0.12,
            emission_hex="#FFE8B5",
            emission_strength=1.10,
            alpha=0.26,
        ),
        "bulb_warm_glow": create_pbr_mat(
            "Mat_Bulb_WarmGlow",
            "#FFECC4",
            roughness=0.15,
            emission_hex="#FFD584",
            emission_strength=2.60,
        ),
        "screen_dark_bg": create_pbr_mat(
            "Mat_Screen_DarkIDE",
            "#252932",
            roughness=0.22,
            emission_hex="#282E3A",
            emission_strength=0.35,
        ),
        "screen_code_green": create_pbr_mat(
            "Mat_Screen_CodeGreen",
            "#9ADCA0",
            roughness=0.15,
            emission_hex="#9ADCA0",
            emission_strength=1.70,
        ),
        "screen_code_warm": create_pbr_mat(
            "Mat_Screen_CodeWarm",
            "#F5C47E",
            roughness=0.15,
            emission_hex="#F5C47E",
            emission_strength=1.55,
        ),
    }


def select_export_hierarchy(export_col: bpy.types.Collection) -> list[bpy.types.Object]:
    bpy.ops.object.select_all(action="DESELECT")
    selected = []
    for obj in export_col.all_objects:
        obj.hide_set(False)
        obj.select_set(True)
        selected.append(obj)
    if selected:
        bpy.context.view_layer.objects.active = selected[0]
    return selected


def main() -> None:
    clear_scene()
    cols = create_asset_collection_tree("CozyStudio")
    export_col = cols["export"]
    mats = build_palette_materials()

    root_venue = create_hierarchy_node(
        "ROOT_Venue_CozyStudio",
        parent=None,
        collection=export_col,
        location=(0.0, 0.0, 0.0),
    )

    build_building_shell(root_venue, export_col, mats)

    grp_zones = create_hierarchy_node(
        "GRP_02_Interior_FunctionalZones",
        parent=root_venue,
        collection=export_col,
        location=(0.0, 0.0, 0.0),
    )
    build_workstation_zone(grp_zones, export_col, mats)
    build_bookshelf_decor_zone(grp_zones, export_col, mats)
    build_coffee_lounge_zone(grp_zones, export_col, mats)

    grp_anchors = create_hierarchy_node(
        "GRP_04_Gameplay_Anchors",
        parent=root_venue,
        collection=export_col,
        location=(0.0, 0.0, 0.0),
    )
    create_hierarchy_node(
        "SOCKET_Spawn_Slacker",
        parent=grp_anchors,
        collection=export_col,
        location=(-0.42, -0.72, 0.02),
        display_type="CUBE",
        display_size=0.08,
    )
    create_hierarchy_node(
        "SOCKET_Spawn_Partner",
        parent=grp_anchors,
        collection=export_col,
        location=(1.28, 0.95, 0.02),
        display_type="CUBE",
        display_size=0.08,
    )

    bpy.context.view_layer.update()

    blend_out = os.path.join(SCRIPT_DIR, "mdl_cozy_studio_room.blend")
    bpy.ops.wm.save_as_mainfile(filepath=blend_out)

    test_root = os.path.dirname(SCRIPT_DIR)
    models_dir = os.path.join(test_root, "assets", "models")
    os.makedirs(models_dir, exist_ok=True)
    glb_out = os.path.join(models_dir, "mdl_cozy_studio_room.glb")

    select_export_hierarchy(export_col)
    bpy.ops.export_scene.gltf(
        filepath=glb_out,
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_materials="EXPORT",
    )
    print(f"[CozyStudio] Saved High-Craft BLEND: {blend_out}")
    print(f"[CozyStudio] Exported High-Craft GLB: {glb_out}")


if __name__ == "__main__":
    main()
