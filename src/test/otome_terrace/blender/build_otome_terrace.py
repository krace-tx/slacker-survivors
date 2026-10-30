# -*- coding: utf-8 -*-
"""Master Builder for Open-Air Cozy Lakeside Blossom Terrace (`mdl_otome_terrace_stage.glb`)."""

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
from zone_terrain_and_lake import build_open_air_terrain_and_horizon  # noqa: E402
from zone_interactive_props import build_interactive_zones_and_lights  # noqa: E402


def build_palette_materials() -> dict[str, bpy.types.Material]:
    """Curated Makoto-Shinkai / Cozy Otome sunlit lakeside park color palette."""
    return {
        "grass_fresh": create_pbr_mat("Mat_Grass_Fresh", "#6EB857", roughness=0.78),
        "grass_soft": create_pbr_mat("Mat_Grass_SoftSun", "#85CA69", roughness=0.76),
        "hedge_deep": create_pbr_mat("Mat_Hedge_DeepGreen", "#46803B", roughness=0.72),
        "leaf_fresh": create_pbr_mat("Mat_Leaf_Botanical", "#5E9E4E", roughness=0.62),
        "cobble_warm_a": create_pbr_mat("Mat_Cobble_WarmSand", "#E6DBC9", roughness=0.72),
        "cobble_warm_b": create_pbr_mat("Mat_Cobble_TaupeStone", "#D6C6B1", roughness=0.74),
        "cobble_curb": create_pbr_mat("Mat_Cobble_CreamCurb", "#F1E8DA", roughness=0.68),
        "cobble_mortar": create_pbr_mat("Mat_Cobble_Mortar", "#BFB09C", roughness=0.84),
        "cedar_plank_a": create_pbr_mat("Mat_Cedar_WarmA", "#CA8B56", roughness=0.54),
        "cedar_plank_b": create_pbr_mat("Mat_Cedar_WarmB", "#DA9D68", roughness=0.52),
        "wood_oak_warm": create_pbr_mat("Mat_Oak_Honey", "#C1804B", roughness=0.55),
        "wood_walnut": create_pbr_mat("Mat_Wood_Walnut", "#7E4B28", roughness=0.52),
        "balustrade_cream": create_pbr_mat("Mat_Stone_Balustrade", "#EFE6D6", roughness=0.66),
        "balustrade_light": create_pbr_mat("Mat_Stone_BalustradeLight", "#F8F1E5", roughness=0.64),
        "tree_bark": create_pbr_mat("Mat_Cherry_Bark", "#5E4032", roughness=0.80),
        "blossom_pink": create_pbr_mat(
            "Mat_Blossom_Pink",
            "#FAD0DE",
            roughness=0.68,
            emission_hex="#FFE2EC",
            emission_strength=0.14,
        ),
        "blossom_ivory": create_pbr_mat(
            "Mat_Blossom_Ivory",
            "#FFF2F6",
            roughness=0.68,
            emission_hex="#FFF7FA",
            emission_strength=0.16,
        ),
        "blossom_deep": create_pbr_mat("Mat_Blossom_Rose", "#F2B0C6", roughness=0.70),
        "iron_forest": create_pbr_mat("Mat_Iron_ForestBench", "#2E4739", roughness=0.44, metallic=0.35),
        "iron_lamp": create_pbr_mat("Mat_Iron_Charcoal", "#32353B", roughness=0.42, metallic=0.45),
        "brass": create_pbr_mat("Mat_Warm_Brass", "#E6B456", roughness=0.30, metallic=0.68),
        "cart_cream": create_pbr_mat("Mat_Cart_WarmCream", "#FDF6E9", roughness=0.58),
        "parasol_taupe": create_pbr_mat("Mat_Parasol_Taupe", "#D8BEA2", roughness=0.68),
        "hydrangea_blue": create_pbr_mat("Mat_Hydrangea_Blue", "#88A8F2", roughness=0.66),
        "hydrangea_lavender": create_pbr_mat("Mat_Hydrangea_Lavender", "#B89FF0", roughness=0.66),
        "fountain_water": create_pbr_mat(
            "Mat_Fountain_Water",
            "#72D7EE",
            roughness=0.10,
            emission_hex="#9CE8F8",
            emission_strength=0.22,
            alpha=0.82,
        ),
        "glass_clear": create_pbr_mat("Mat_Display_Glass", "#F2FAFC", roughness=0.10, alpha=0.32),
        "lake_deep": create_pbr_mat("Mat_Lake_Deep", "#3596B5", roughness=0.35),
        "lake_surface": create_pbr_mat(
            "Mat_Lake_Turquoise",
            "#5BC4DF",
            roughness=0.12,
            emission_hex="#7AD8EE",
            emission_strength=0.16,
            alpha=0.92,
        ),
        "hill_near": create_pbr_mat("Mat_Hill_MeadowNear", "#76B67D", roughness=0.84),
        "hill_mid": create_pbr_mat("Mat_Hill_MeadowMid", "#86C28E", roughness=0.86),
        "hill_far": create_pbr_mat("Mat_Hill_MistyFar", "#9BD0A8", roughness=0.88),
        "bulb_warm_glow": create_pbr_mat(
            "Mat_Bulb_WarmFestoon",
            "#FFF0CC",
            roughness=0.15,
            emission_hex="#FFD685",
            emission_strength=2.80,
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


def build_otome_terrace_scene() -> tuple[str, str]:
    clear_scene()
    cols = create_asset_collection_tree("OtomeTerrace")
    export_col = cols["export"]
    mats = build_palette_materials()

    root_venue = create_hierarchy_node(
        "ROOT_Venue_OtomeTerrace",
        parent=None,
        collection=export_col,
        location=(0.0, 0.0, 0.0),
    )

    build_open_air_terrain_and_horizon(root_venue, export_col, mats)
    build_interactive_zones_and_lights(root_venue, export_col, mats)

    grp_anchors = create_hierarchy_node(
        "GRP_04_Gameplay_Anchors",
        parent=root_venue,
        collection=export_col,
        location=(0.0, 0.0, 0.0),
    )
    anchor_defs = [
        ("SOCKET_Spawn_Hero", (-1.15, -1.15, 0.03)),
        ("SOCKET_Spot_BlossomBench", (-2.15, 0.25, 0.03)),
        ("SOCKET_Spot_CoffeeCart", (0.55, 2.15, 0.18)),
        ("SOCKET_Spot_LakesideFountain", (2.15, -0.35, 0.03)),
    ]
    for sock_name, sock_loc in anchor_defs:
        create_hierarchy_node(
            sock_name,
            parent=grp_anchors,
            collection=export_col,
            location=sock_loc,
            display_type="CUBE",
            display_size=0.08,
        )

    bpy.context.view_layer.update()

    blend_out = os.path.join(SCRIPT_DIR, "mdl_otome_terrace_stage.blend")
    bpy.ops.wm.save_as_mainfile(filepath=blend_out)

    test_root = os.path.dirname(SCRIPT_DIR)
    models_dir = os.path.join(test_root, "assets", "models")
    os.makedirs(models_dir, exist_ok=True)
    glb_out = os.path.join(models_dir, "mdl_otome_terrace_stage.glb")

    select_export_hierarchy(export_col)
    bpy.ops.export_scene.gltf(
        filepath=glb_out,
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_materials="EXPORT",
    )
    print(f"[OtomeTerrace] Saved BLEND: {blend_out}")
    print(f"[OtomeTerrace] Exported GLB: {glb_out}")
    return blend_out, glb_out


if __name__ == "__main__":
    build_otome_terrace_scene()
