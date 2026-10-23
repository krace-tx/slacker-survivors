"""系统模块 (System Module)：心跳检测与运行环境信息。"""
from __future__ import annotations

try:
    import bpy
except ImportError:
    bpy = None  # type: ignore[assignment]

from ...shared.protocol import METHOD_PING
from .base_module import BaseModule, CommandRegistry


class SystemModule(BaseModule):

    def register_commands(self, registry: CommandRegistry) -> None:
        registry.register_command(
            METHOD_PING,
            "Health check. Returns 'pong' with the Blender version.",
            {},
            self._ping,
            undoable=False,
        )
        registry.register_command(
            "system.info",
            "Get Blender runtime info: version, open .blend file, unsaved state, render engines.",
            {},
            self._info,
            undoable=False,
        )

    def _ping(self, _p: dict) -> dict:
        return {"status": "pong", "blender_version": self.ctx.blender_version()}

    def _info(self, _p: dict) -> dict:
        render = self.ctx.scene.render
        return {
            "blender_version": self.ctx.blender_version(),
            "python_version": ".".join(str(v) for v in __import__("sys").version_info[:3]),
            "filepath": bpy.data.filepath or None,
            "is_dirty": bpy.data.is_dirty,
            "background": bpy.app.background,
            "render_engine": render.engine,
            "available_engines": [i.identifier for i in render.bl_rna.properties["engine"].enum_items],
        }
