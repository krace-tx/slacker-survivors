"""对象模块 (Object Module)：删除、重命名、变换、复制、合并。

这些操作适用于任意类型的对象（网格 / 相机 / 灯光 / 空物体），
因此从旧版 ``mesh.*`` 命名空间迁移至 ``object.*``，旧名称保留为别名。
"""
from __future__ import annotations

try:
    import bpy
except ImportError:
    bpy = None  # type: ignore[assignment]

from .base_module import BaseModule, CommandRegistry, RpcError


class ObjectModule(BaseModule):

    def register_commands(self, registry: CommandRegistry) -> None:
        registry.register_command(
            "object.get_info",
            "Get detailed info of an object: transform, dimensions, topology, materials, modifiers.",
            {"object_name": {"type": "string", "required": True, "description": "Object name"}},
            self._get_info,
            undoable=False,
        )

        registry.register_command(
            "object.delete",
            "⚠️ Destructive: delete objects by name.",
            {"object_names": {"type": "array", "required": True, "description": "Names of objects to delete"}},
            self._delete,
        )
        registry.register_alias("mesh.delete", "object.delete")

        registry.register_command(
            "object.rename",
            "Rename an object (its exclusively-owned data block is renamed too).",
            {
                "old_name": {"type": "string", "required": True, "description": "Current object name"},
                "new_name": {"type": "string", "required": True, "description": "New object name"},
            },
            self._rename,
        )
        registry.register_alias("mesh.rename", "object.rename")

        registry.register_command(
            "object.transform",
            "Set location / rotation (radians) / scale of an object. Omitted fields stay unchanged.",
            {
                "object_name": {"type": "string", "required": True, "description": "Object name"},
                "location": {"type": "vec3", "description": "[x, y, z] world position"},
                "rotation": {"type": "vec3", "description": "[rx, ry, rz] Euler rotation in radians"},
                "scale": {"type": "vec3", "description": "[sx, sy, sz] scale"},
            },
            self._transform,
        )
        registry.register_alias("mesh.transform", "object.transform")

        registry.register_command(
            "object.duplicate",
            "Duplicate an object (deep-copies its data) with an optional position offset.",
            {
                "object_name": {"type": "string", "required": True, "description": "Object to duplicate"},
                "new_name": {"type": "string", "description": "Name of the copy"},
                "offset": {"type": "vec3", "default": [0.0, 0.0, 0.0], "description": "[x, y, z] offset"},
                "linked": {"type": "bool", "default": False,
                           "description": "Share mesh data with the original (linked duplicate)"},
            },
            self._duplicate,
        )
        registry.register_alias("mesh.duplicate", "object.duplicate")

        registry.register_command(
            "object.join",
            "Join multiple mesh objects into one. The first object is the join target.",
            {
                "object_names": {"type": "array", "required": True, "description": "At least 2 mesh objects"},
                "result_name": {"type": "string", "description": "Name of the merged object"},
            },
            self._join,
        )
        registry.register_alias("mesh.join", "object.join")

    # ── handlers ───────────────────────────────────────────────

    def _get_info(self, p: dict) -> dict:
        return self.ctx.object_info(self.ctx.get_object(p["object_name"]), detailed=True)

    def _delete(self, p: dict) -> dict:
        deleted, not_found = [], []
        for name in p["object_names"]:
            obj = bpy.data.objects.get(name)
            if obj is None:
                not_found.append(name)
                continue
            self.ctx.remove_object(obj)
            deleted.append(name)
        return {"deleted": deleted, "not_found": not_found}

    def _rename(self, p: dict) -> dict:
        obj = self.ctx.get_object(p["old_name"])
        self.ctx.rename(obj, p["new_name"])
        # Blender 在名称冲突时会自动追加 .001 后缀，返回实际名称
        return {"old_name": p["old_name"], "new_name": obj.name}

    def _transform(self, p: dict) -> dict:
        obj = self.ctx.get_object(p["object_name"])
        if "location" in p:
            obj.location = p["location"]
        if "rotation" in p:
            obj.rotation_euler = p["rotation"]
        if "scale" in p:
            obj.scale = p["scale"]
        return self.ctx.object_info(obj)

    def _duplicate(self, p: dict) -> dict:
        src = self.ctx.get_object(p["object_name"])
        dup = src.copy()
        if src.data is not None and not p["linked"]:
            dup.data = src.data.copy()
        self.ctx.link_object(dup)
        if p.get("new_name"):
            self.ctx.rename(dup, p["new_name"])
        dup.location = [a + b for a, b in zip(src.location, p["offset"])]
        return self.ctx.object_info(dup)

    def _join(self, p: dict) -> dict:
        names = p["object_names"]
        if len(names) < 2:
            raise RpcError.invalid_params("Need at least 2 objects to join", {"count": len(names)})
        objects = self.ctx.get_objects(names)
        for obj in objects:
            self.ctx.require_type(obj, "MESH")

        target = objects[0]
        self.ctx.ensure_object_mode()
        self.ctx.select(objects, active=target)
        with self.ctx.ops_context(active_object=target, selected_editable_objects=objects,
                                  selected_objects=objects):
            bpy.ops.object.join()

        if p.get("result_name"):
            self.ctx.rename(target, p["result_name"])
        return self.ctx.object_info(target)
