"""灯光模块 (Light Module)：光源创建与世界 HDRI 环境。"""
from __future__ import annotations

import os

try:
    import bpy
except ImportError:
    bpy = None  # type: ignore[assignment]

from .base_module import BaseModule, CommandRegistry, RpcError


class LightModule(BaseModule):

    def register_commands(self, registry: CommandRegistry) -> None:
        registry.register_command(
            "light.create",
            "Create a light source.",
            {
                "name": {"type": "string", "default": "Light", "description": "Light name"},
                "type": {"type": "string", "default": "POINT", "enum": ["POINT", "SUN", "SPOT", "AREA"],
                         "description": "Light type"},
                "location": {"type": "vec3", "default": [0.0, 0.0, 0.0], "description": "[x, y, z] position"},
                "rotation": {"type": "vec3", "default": [0.0, 0.0, 0.0], "description": "[rx, ry, rz] radians"},
                "energy": {"type": "float", "default": 1000.0,
                           "description": "Power in watts (SUN: irradiance in W/m², typically 1~10)"},
                "color": {"type": "color", "default": [1.0, 1.0, 1.0], "description": "[r, g, b] 0~1"},
                "radius": {"type": "float", "default": 0.25, "description": "Soft shadow radius / size"},
            },
            self._create,
        )

        registry.register_command(
            "light.set_world_hdri",
            "Use an HDRI (.hdr / .exr) image as world environment lighting.",
            {
                "hdri_path": {"type": "string", "required": True, "description": "Absolute path to .hdr / .exr"},
                "strength": {"type": "float", "default": 1.0, "description": "Background strength"},
                "rotation_z": {"type": "float", "default": 0.0, "description": "Environment Z rotation (radians)"},
            },
            self._set_world_hdri,
        )

    # ── handlers ───────────────────────────────────────────────

    def _create(self, p: dict) -> dict:
        light_data = bpy.data.lights.new(name=p["name"], type=p["type"])
        light_data.energy = p["energy"]
        light_data.color = p["color"][:3]
        light_data.shadow_soft_size = p["radius"]

        light = self.ctx.link_object(bpy.data.objects.new(name=p["name"], object_data=light_data))
        light.location = p["location"]
        light.rotation_euler = p["rotation"]
        return {
            "name": light.name,
            "type": light_data.type,
            "energy": light_data.energy,
            "color": self.ctx.vec(light_data.color),
            "location": self.ctx.vec(light.location),
        }

    def _set_world_hdri(self, p: dict) -> dict:
        path = p["hdri_path"]
        if not os.path.isfile(path):
            raise RpcError.not_found(f"HDRI file not found: {path}", {"hdri_path": path})

        scene = self.ctx.scene
        world = scene.world or bpy.data.worlds.new(name="World")
        scene.world = world
        world.use_nodes = True
        tree = world.node_tree
        tree.nodes.clear()

        tex_coord = tree.nodes.new("ShaderNodeTexCoord")
        mapping = tree.nodes.new("ShaderNodeMapping")
        env_tex = tree.nodes.new("ShaderNodeTexEnvironment")
        background = tree.nodes.new("ShaderNodeBackground")
        output = tree.nodes.new("ShaderNodeOutputWorld")
        for i, node in enumerate((tex_coord, mapping, env_tex, background, output)):
            node.location = (i * 250 - 500, 0)

        env_tex.image = bpy.data.images.load(path, check_existing=True)
        mapping.inputs["Rotation"].default_value[2] = p["rotation_z"]
        background.inputs["Strength"].default_value = p["strength"]

        tree.links.new(tex_coord.outputs["Generated"], mapping.inputs["Vector"])
        tree.links.new(mapping.outputs["Vector"], env_tex.inputs["Vector"])
        tree.links.new(env_tex.outputs["Color"], background.inputs["Color"])
        tree.links.new(background.outputs["Background"], output.inputs["Surface"])
        return {"world": world.name, "hdri": path, "strength": p["strength"]}
