"""材质模块 (Material Module)：PBR 材质的创建、分配、调色、列出与删除。"""
from __future__ import annotations

try:
    import bpy
except ImportError:
    bpy = None  # type: ignore[assignment]

from .base_module import BaseModule, CommandRegistry, RpcError


class MaterialModule(BaseModule):

    def register_commands(self, registry: CommandRegistry) -> None:
        registry.register_command(
            "material.create",
            "Create a new Principled BSDF (PBR) material.",
            {
                "name": {"type": "string", "required": True, "description": "Material name"},
                "color": {"type": "color", "default": [0.8, 0.8, 0.8, 1.0], "description": "[r, g, b(, a)] 0~1"},
                "metallic": {"type": "float", "default": 0.0, "description": "Metallic 0~1"},
                "roughness": {"type": "float", "default": 0.5, "description": "Roughness 0~1"},
                "emission_color": {"type": "color", "description": "[r, g, b(, a)] emission color"},
                "emission_strength": {"type": "float", "description": "Emission strength"},
            },
            self._create,
        )

        registry.register_command(
            "material.assign",
            "Assign an existing material to an object (replaces slot 0, or a given slot index).",
            {
                "object_name": {"type": "string", "required": True, "description": "Target object"},
                "material_name": {"type": "string", "required": True, "description": "Material to assign"},
                "slot": {"type": "int", "default": 0, "description": "Material slot index"},
            },
            self._assign,
        )

        registry.register_command(
            "material.set_color",
            "Set base color of an object's first material (auto-creates a material if none).",
            {
                "object_name": {"type": "string", "required": True, "description": "Target object"},
                "color": {"type": "color", "required": True, "description": "[r, g, b(, a)] 0~1"},
            },
            self._set_color,
        )

        registry.register_command(
            "material.list",
            "List all materials in the current .blend file.",
            {},
            self._list,
            undoable=False,
        )

        registry.register_command(
            "material.delete",
            "⚠️ Destructive: delete a material by name.",
            {"material_name": {"type": "string", "required": True, "description": "Material to delete"}},
            self._delete,
        )

    # ── handlers ───────────────────────────────────────────────

    def _create(self, p: dict) -> dict:
        mat = bpy.data.materials.new(name=p["name"])
        mat.use_nodes = True
        bsdf = self.ctx.principled_bsdf(mat)
        if bsdf is None:
            raise RpcError.execution_error(f"Material '{mat.name}' has no Principled BSDF node")

        bsdf.inputs["Base Color"].default_value = self.ctx.rgba(p["color"])
        bsdf.inputs["Metallic"].default_value = p["metallic"]
        bsdf.inputs["Roughness"].default_value = p["roughness"]
        if "emission_color" in p:
            # Blender 4.0+ 输入名为 "Emission Color"，3.x 为 "Emission"
            socket = bsdf.inputs.get("Emission Color") or bsdf.inputs.get("Emission")
            if socket is not None:
                socket.default_value = self.ctx.rgba(p["emission_color"])
        if "emission_strength" in p and "Emission Strength" in bsdf.inputs:
            bsdf.inputs["Emission Strength"].default_value = p["emission_strength"]
        return self._info(mat)

    def _assign(self, p: dict) -> dict:
        obj = self.ctx.get_object(p["object_name"])
        self.ctx.require_material_slots(obj)
        mat = self.ctx.get_material(p["material_name"])
        slots = obj.data.materials
        slot = p["slot"]
        if slot < 0 or slot > len(slots):
            raise RpcError.invalid_params(f"Slot {slot} out of range (object has {len(slots)} slots)")
        if slot == len(slots):
            slots.append(mat)
        else:
            slots[slot] = mat
        return {"object": obj.name, "material": mat.name, "slot": slot}

    def _set_color(self, p: dict) -> dict:
        obj = self.ctx.get_object(p["object_name"])
        self.ctx.require_material_slots(obj)
        if not obj.data.materials or obj.data.materials[0] is None:
            mat = bpy.data.materials.new(name=f"{obj.name}_Material")
            mat.use_nodes = True
            if obj.data.materials:
                obj.data.materials[0] = mat
            else:
                obj.data.materials.append(mat)
        mat = obj.data.materials[0]
        rgba = self.ctx.rgba(p["color"])
        bsdf = self.ctx.principled_bsdf(mat)
        if bsdf is not None:
            bsdf.inputs["Base Color"].default_value = rgba
        mat.diffuse_color = rgba  # 同步视口显示色
        return {"object": obj.name, "material": mat.name, "color": list(rgba)}

    def _list(self, _p: dict) -> dict:
        mats = [self._info(m) for m in bpy.data.materials]
        return {"count": len(mats), "materials": mats}

    def _delete(self, p: dict) -> dict:
        mat = self.ctx.get_material(p["material_name"])
        bpy.data.materials.remove(mat)
        return {"deleted": p["material_name"]}

    # ── 内部 ───────────────────────────────────────────────────

    def _info(self, mat: bpy.types.Material) -> dict:
        info: dict = {"name": mat.name, "users": mat.users}
        bsdf = self.ctx.principled_bsdf(mat)
        if bsdf is not None:
            info["base_color"] = self.ctx.vec(bsdf.inputs["Base Color"].default_value)
            info["metallic"] = round(bsdf.inputs["Metallic"].default_value, 4)
            info["roughness"] = round(bsdf.inputs["Roughness"].default_value, 4)
        return info
