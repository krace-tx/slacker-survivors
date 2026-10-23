"""网格模块 (Mesh Module)：基本体创建与着色。"""
from __future__ import annotations

from typing import Any, Callable

try:
    import bpy
except ImportError:
    bpy = None  # type: ignore[assignment]

from .base_module import BaseModule, CommandRegistry

# 基本体类型 → (算子, 参数构造函数(size, segments, rings))
_PRIMITIVES: dict[str, tuple[str, Callable[[float, int, int], dict[str, Any]]]] = {
    "cube": ("primitive_cube_add", lambda s, seg, r: {"size": s}),
    "sphere": ("primitive_uv_sphere_add",
               lambda s, seg, r: {"radius": s / 2, "segments": seg, "ring_count": r}),
    "ico_sphere": ("primitive_ico_sphere_add",
                   lambda s, seg, r: {"radius": s / 2, "subdivisions": max(1, min(seg, 8))}),
    "cylinder": ("primitive_cylinder_add",
                 lambda s, seg, r: {"radius": s / 2, "depth": s, "vertices": seg}),
    "cone": ("primitive_cone_add",
             lambda s, seg, r: {"radius1": s / 2, "depth": s, "vertices": seg}),
    "torus": ("primitive_torus_add",
              lambda s, seg, r: {"major_radius": s, "minor_radius": s * 0.25,
                                 "major_segments": seg, "minor_segments": r}),
    "plane": ("primitive_plane_add", lambda s, seg, r: {"size": s}),
    "circle": ("primitive_circle_add", lambda s, seg, r: {"radius": s / 2, "vertices": seg}),
    "monkey": ("primitive_monkey_add", lambda s, seg, r: {"size": s}),
    "grid": ("primitive_grid_add",
             lambda s, seg, r: {"size": s, "x_subdivisions": seg, "y_subdivisions": seg}),
}
_ALIASES = {"uv_sphere": "sphere"}


class MeshModule(BaseModule):

    def register_commands(self, registry: CommandRegistry) -> None:
        registry.register_command(
            "mesh.add_primitive",
            "Add a primitive mesh object to the scene.",
            {
                "type": {"type": "string", "default": "cube", "enum": [*_PRIMITIVES, *_ALIASES],
                         "description": "Primitive type"},
                "name": {"type": "string", "description": "Custom object name"},
                "location": {"type": "vec3", "default": [0.0, 0.0, 0.0], "description": "[x, y, z] position"},
                "rotation": {"type": "vec3", "default": [0.0, 0.0, 0.0], "description": "[rx, ry, rz] radians"},
                "scale": {"type": "vec3", "default": [1.0, 1.0, 1.0], "description": "[sx, sy, sz] scale"},
                "size": {"type": "float", "default": 1.0, "description": "Size / diameter of the primitive"},
                "segments": {"type": "int", "default": 32, "description": "Segments for curved primitives"},
                "rings": {"type": "int", "default": 16, "description": "Rings for sphere / torus"},
            },
            self._add_primitive,
        )

        registry.register_command(
            "mesh.set_smooth",
            "Set smooth or flat shading on a mesh object.",
            {
                "object_name": {"type": "string", "required": True, "description": "Mesh object name"},
                "smooth": {"type": "bool", "default": True, "description": "True = smooth, False = flat"},
            },
            self._set_smooth,
        )

    # ── handlers ───────────────────────────────────────────────

    def _add_primitive(self, p: dict) -> dict:
        ptype = _ALIASES.get(p["type"], p["type"])
        op_name, build_args = _PRIMITIVES[ptype]
        op_args = build_args(p["size"], p["segments"], p["rings"])

        self.ctx.ensure_object_mode()
        with self.ctx.ops_context():
            getattr(bpy.ops.mesh, op_name)(location=p["location"], rotation=p["rotation"], **op_args)

        obj = self.ctx.active_object
        if p.get("name"):
            self.ctx.rename(obj, p["name"])
        obj.scale = p["scale"]
        return self.ctx.object_info(obj)

    def _set_smooth(self, p: dict) -> dict:
        obj = self.ctx.require_type(self.ctx.get_object(p["object_name"]), "MESH")
        smooth = p["smooth"]
        obj.data.polygons.foreach_set("use_smooth", [smooth] * len(obj.data.polygons))
        obj.data.update()
        return {"object": obj.name, "smooth": smooth}
