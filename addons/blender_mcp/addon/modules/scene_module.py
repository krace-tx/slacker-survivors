"""场景模块 (Scene Module)：场景信息、对象列表、清空、选择、撤销 / 重做。

这些指令作用于整个场景状态，而非单个对象属性。
"""
from __future__ import annotations

try:
    import bpy
except ImportError:
    bpy = None  # type: ignore[assignment]

from .base_module import BaseModule, CommandRegistry, RpcError

_OBJECT_TYPES = ["MESH", "CURVE", "SURFACE", "META", "FONT", "ARMATURE", "LATTICE",
                 "EMPTY", "GPENCIL", "GREASEPENCIL", "CAMERA", "LIGHT", "LIGHT_PROBE", "SPEAKER"]


class SceneModule(BaseModule):

    def register_commands(self, registry: CommandRegistry) -> None:
        registry.register_command(
            "scene.get_info",
            "Get current scene info: name, frame range, FPS, render engine, selection.",
            {},
            self._get_info,
            undoable=False,
        )

        registry.register_command(
            "scene.list_objects",
            "List all objects in the current scene, optionally filtered by type.",
            {
                "type_filter": {"type": "string", "enum": _OBJECT_TYPES,
                                "description": "Only list objects of this type (e.g. MESH, CAMERA, LIGHT)"},
            },
            self._list_objects,
            undoable=False,
        )

        registry.register_command(
            "scene.clear",
            "⚠️ Destructive: delete objects from the scene by type ('ALL' deletes everything).",
            {
                "type_filter": {"type": "string", "default": "MESH", "enum": ["ALL", *_OBJECT_TYPES],
                                "description": "Object type to delete, or ALL"},
            },
            self._clear,
        )

        registry.register_command(
            "scene.select",
            "Select / deselect objects. With object_names, the first found object becomes active.",
            {
                "object_names": {"type": "array", "default": [], "description": "Objects to select"},
                "all": {"type": "bool", "default": False, "description": "Apply to all objects"},
                "deselect": {"type": "bool", "default": False, "description": "Deselect instead of select"},
                "replace": {"type": "bool", "default": False,
                            "description": "Clear existing selection before selecting object_names"},
            },
            self._select,
            undoable=False,
        )

        registry.register_command(
            "scene.undo",
            "Undo the last operation (equivalent to Ctrl+Z).",
            {},
            self._undo,
            undoable=False,
        )

        registry.register_command(
            "scene.redo",
            "Redo the last undone operation (equivalent to Ctrl+Shift+Z).",
            {},
            self._redo,
            undoable=False,
        )

    # ── handlers ───────────────────────────────────────────────

    def _get_info(self, _p: dict) -> dict:
        scene = self.ctx.scene
        active = self.ctx.active_object
        return {
            "name": scene.name,
            "frame_start": scene.frame_start,
            "frame_end": scene.frame_end,
            "frame_current": scene.frame_current,
            "fps": scene.render.fps,
            "render_engine": scene.render.engine,
            "resolution": [scene.render.resolution_x, scene.render.resolution_y],
            "unit_system": scene.unit_settings.system,
            "object_count": len(scene.objects),
            "active_camera": scene.camera.name if scene.camera else None,
            "selected_objects": [o.name for o in scene.objects if o.select_get()],
            "active_object": active.name if active else None,
        }

    def _list_objects(self, p: dict) -> dict:
        type_filter = p.get("type_filter")
        objects = [
            self.ctx.object_info(obj, detailed=True)
            for obj in self.ctx.scene.objects
            if not type_filter or obj.type == type_filter
        ]
        return {"count": len(objects), "objects": objects}

    def _clear(self, p: dict) -> dict:
        type_filter = p["type_filter"]
        targets = [o for o in self.ctx.scene.objects if type_filter == "ALL" or o.type == type_filter]
        names = [o.name for o in targets]
        for obj in targets:
            self.ctx.remove_object(obj)
        return {"deleted_count": len(names), "deleted_objects": names}

    def _select(self, p: dict) -> dict:
        if p["all"]:
            for obj in self.ctx.view_layer.objects:
                obj.select_set(not p["deselect"])
            return {"action": "deselect_all" if p["deselect"] else "select_all"}

        found, not_found = [], []
        for name in p["object_names"]:
            obj = bpy.data.objects.get(name)
            (found if obj else not_found).append(obj or name)

        if p["deselect"]:
            for obj in found:
                obj.select_set(False)
        else:
            self.ctx.select(found, active=found[0] if found else None, replace=p["replace"])

        return {
            "action": "deselect" if p["deselect"] else "select",
            "affected": [o.name for o in found],
            "not_found": not_found,
        }

    def _undo(self, _p: dict) -> dict:
        self._run_history_op(bpy.ops.ed.undo, "undo")
        return {"message": "Undo performed"}

    def _redo(self, _p: dict) -> dict:
        self._run_history_op(bpy.ops.ed.redo, "redo")
        return {"message": "Redo performed"}

    def _run_history_op(self, op, label: str) -> None:
        with self.ctx.ops_context():
            if not op.poll():
                raise RpcError.invalid_state(f"Nothing to {label}")
            op()
