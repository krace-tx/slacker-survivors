"""修改器模块 (Modifier Module)：添加、应用、移除、列出修改器。"""
from __future__ import annotations

from typing import Any

try:
    import bpy
except ImportError:
    bpy = None  # type: ignore[assignment]

from .base_module import BaseModule, CommandRegistry, RpcError

# 各类型修改器在回包中报告的关键属性
_KEY_PROPS: dict[str, tuple[str, ...]] = {
    "SUBSURF": ("levels", "render_levels"),
    "MIRROR": ("use_axis", "use_clip", "mirror_object"),
    "ARRAY": ("count", "relative_offset_displace"),
    "SOLIDIFY": ("thickness", "offset"),
    "BEVEL": ("width", "segments", "limit_method"),
    "DECIMATE": ("decimate_type", "ratio"),
    "BOOLEAN": ("operation", "object", "solver"),
    "SMOOTH": ("factor", "iterations"),
    "WEIGHTED_NORMAL": ("weight", "keep_sharp"),
}


def _serialize(value: Any) -> Any:
    if isinstance(value, bpy.types.ID):
        return value.name
    if isinstance(value, (str, int, float, bool)) or value is None:
        return value
    try:
        return [round(v, 4) if isinstance(v, float) else v for v in value]
    except TypeError:
        return str(value)


class ModifierModule(BaseModule):

    def register_commands(self, registry: CommandRegistry) -> None:
        registry.register_command(
            "modifier.add",
            "Add a modifier to an object, optionally setting modifier-specific properties.",
            {
                "object_name": {"type": "string", "required": True, "description": "Target object"},
                "type": {"type": "string", "default": "SUBSURF",
                         "description": "Modifier type: SUBSURF, MIRROR, BOOLEAN, SOLIDIFY, ARRAY, BEVEL, "
                                        "DECIMATE, SMOOTH, WEIGHTED_NORMAL, SHRINKWRAP, SIMPLE_DEFORM ..."},
                "name": {"type": "string", "description": "Custom modifier name"},
                "properties": {"type": "object", "default": {},
                               "description": "Modifier properties, e.g. {\"levels\": 2}. "
                                              "Object references (e.g. BOOLEAN 'object') accept object names."},
            },
            self._add,
        )

        registry.register_command(
            "modifier.apply",
            "Apply (bake) a modifier permanently onto the mesh.",
            {
                "object_name": {"type": "string", "required": True, "description": "Target object"},
                "modifier_name": {"type": "string", "required": True, "description": "Modifier to apply"},
            },
            self._apply,
        )

        registry.register_command(
            "modifier.remove",
            "Remove a modifier from an object.",
            {
                "object_name": {"type": "string", "required": True, "description": "Target object"},
                "modifier_name": {"type": "string", "required": True, "description": "Modifier to remove"},
            },
            self._remove,
        )

        registry.register_command(
            "modifier.list",
            "List all modifiers on an object.",
            {"object_name": {"type": "string", "required": True, "description": "Target object"}},
            self._list,
            undoable=False,
        )

    # ── handlers ───────────────────────────────────────────────

    def _add(self, p: dict) -> dict:
        obj = self.ctx.get_object(p["object_name"])
        mod_type = p["type"].upper()
        valid = [i.identifier for i in bpy.types.Modifier.bl_rna.properties["type"].enum_items]
        if mod_type not in valid:
            raise RpcError.invalid_params(f"Unknown modifier type '{p['type']}'", {"available": valid})

        mod = obj.modifiers.new(name=p.get("name") or mod_type.title(), type=mod_type)

        # 兼容旧协议：属性平铺在顶层参数中（宽松模式透传进来的额外字段）
        props: dict[str, Any] = dict(p["properties"])
        reserved = {"object_name", "type", "name", "properties"}
        props.update({k: v for k, v in p.items() if k not in reserved})

        applied, ignored = self._apply_props(mod, props)
        return {
            "object": obj.name,
            "modifier": mod.name,
            "type": mod.type,
            "applied_properties": applied,
            "ignored_properties": ignored,
            **self._key_props(mod),
        }

    def _apply(self, p: dict) -> dict:
        obj = self.ctx.get_object(p["object_name"])
        mod = self.ctx.get_modifier(obj, p["modifier_name"])
        name = mod.name
        self.ctx.ensure_object_mode()
        with self.ctx.ops_context(object=obj, active_object=obj):
            bpy.ops.object.modifier_apply(modifier=name)
        return {"applied": name, **self.ctx.object_info(obj)}

    def _remove(self, p: dict) -> dict:
        obj = self.ctx.get_object(p["object_name"])
        mod = self.ctx.get_modifier(obj, p["modifier_name"])
        obj.modifiers.remove(mod)
        return {"object": obj.name, "removed": p["modifier_name"]}

    def _list(self, p: dict) -> dict:
        obj = self.ctx.get_object(p["object_name"])
        mods = [
            {
                "name": m.name,
                "type": m.type,
                "show_viewport": m.show_viewport,
                "show_render": m.show_render,
                **self._key_props(m),
            }
            for m in obj.modifiers
        ]
        return {"object": obj.name, "count": len(mods), "modifiers": mods}

    # ── 内部 ───────────────────────────────────────────────────

    @staticmethod
    def _apply_props(mod: bpy.types.Modifier, props: dict[str, Any]) -> tuple[list[str], dict[str, str]]:
        applied: list[str] = []
        ignored: dict[str, str] = {}
        for key, value in props.items():
            if not hasattr(mod, key):
                ignored[key] = "unknown property"
                continue
            prop_def = mod.bl_rna.properties.get(key)
            # 指针属性（如 BOOLEAN.object / MIRROR.mirror_object）允许直接传对象名
            if prop_def is not None and prop_def.type == "POINTER" and isinstance(value, str):
                value = bpy.data.objects.get(value)
                if value is None:
                    ignored[key] = f"object '{props[key]}' not found"
                    continue
            try:
                setattr(mod, key, value)
                applied.append(key)
            except (TypeError, ValueError, AttributeError) as exc:
                ignored[key] = str(exc)
        return applied, ignored

    @staticmethod
    def _key_props(mod: bpy.types.Modifier) -> dict[str, Any]:
        return {k: _serialize(getattr(mod, k)) for k in _KEY_PROPS.get(mod.type, ()) if hasattr(mod, k)}
