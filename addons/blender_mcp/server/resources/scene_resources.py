"""场景级 MCP Resources：当前场景信息、对象列表与材质列表。

对齐 Godot MCP ``server/src/resources/scene_resources.ts``。
"""
from __future__ import annotations

from ..utils import fetch_json
from ._group import ResourceGroup

scene_resources = ResourceGroup("scene")


@scene_resources.resource(
    "blender://scene/current",
    name="Blender Current Scene Info",
    description="Metadata of the active Blender scene: frame range, FPS, render engine, resolution, selection.",
)
async def current_scene_resource() -> str:
    return await fetch_json("scene.get_info")


@scene_resources.resource(
    "blender://scene/objects",
    name="Blender Scene Objects",
    description="All objects in the active Blender scene with transform, dimensions, topology, materials and modifiers.",
)
async def scene_objects_resource() -> str:
    return await fetch_json("scene.list_objects")


@scene_resources.resource(
    "blender://scene/materials",
    name="Blender Materials",
    description="All materials in the current .blend file with Principled BSDF parameters.",
)
async def scene_materials_resource() -> str:
    return await fetch_json("material.list")
