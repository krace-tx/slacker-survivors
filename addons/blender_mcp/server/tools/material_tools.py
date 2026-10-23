"""材质 Tools：PBR 材质的创建、分配、调色、列出与删除。"""
from __future__ import annotations

from ..utils import call
from ._group import ToolGroup

material_tools = ToolGroup("material")


@material_tools.tool()
async def blender_create_material(
    name: str,
    color: list[float] | None = None,
    metallic: float | None = None,
    roughness: float | None = None,
    emission_color: list[float] | None = None,
    emission_strength: float | None = None,
) -> str:
    """Create a new Principled BSDF (PBR) material.

    Args:
        name: Material name.
        color: [r, g, b] or [r, g, b, a] base color in 0~1. Default [0.8, 0.8, 0.8, 1].
        metallic: 0~1. Default 0.
        roughness: 0~1. Default 0.5.
        emission_color: [r, g, b(, a)] emission color.
        emission_strength: Emission strength.
    """
    return await call("Create Material", "material.create", name=name, color=color, metallic=metallic,
                      roughness=roughness, emission_color=emission_color, emission_strength=emission_strength)


@material_tools.tool(idempotent=True)
async def blender_assign_material(object_name: str, material_name: str, slot: int | None = None) -> str:
    """Assign an existing material to an object.

    Args:
        object_name: Target object.
        material_name: Material to assign.
        slot: Material slot index. Default 0 (replaces the first material).
    """
    return await call("Assign Material", "material.assign", object_name=object_name,
                      material_name=material_name, slot=slot)


@material_tools.tool(idempotent=True)
async def blender_set_color(object_name: str, color: list[float]) -> str:
    """Set the base color of an object's first material (creates a material if needed).

    Args:
        object_name: Target object.
        color: [r, g, b] or [r, g, b, a] in 0~1.
    """
    return await call("Set Color", "material.set_color", object_name=object_name, color=color)


@material_tools.tool(read_only=True)
async def blender_list_materials() -> str:
    """List all materials in the current .blend file."""
    return await call("Materials", "material.list")


@material_tools.tool(destructive=True)
async def blender_delete_material(material_name: str) -> str:
    """⚠️ Destructive: delete a material by name.

    Args:
        material_name: Material to delete.
    """
    return await call("Delete Material", "material.delete", material_name=material_name)
