"""渲染模块 (Render Module)：完整渲染、视口快照、渲染引擎与分辨率设置。"""
from __future__ import annotations

import contextlib
from typing import Any, Iterator

try:
    import bpy
except ImportError:
    bpy = None  # type: ignore[assignment]

from .base_module import BaseModule, CommandRegistry


class RenderModule(BaseModule):

    def register_commands(self, registry: CommandRegistry) -> None:
        registry.register_command(
            "render.snapshot",
            "Render the scene through the active camera to an image file. Scene render settings "
            "are restored afterwards.",
            {
                "output_path": {"type": "string", "required": True,
                                "description": "Absolute output path; format inferred from extension"},
                "width": {"type": "int", "default": 1920, "description": "Width in pixels"},
                "height": {"type": "int", "default": 1080, "description": "Height in pixels"},
                "samples": {"type": "int", "default": 64, "description": "Render samples"},
                "engine": {"type": "string",
                           "description": "EEVEE / CYCLES / WORKBENCH (or exact identifier). Omit to keep current"},
                "transparent": {"type": "bool", "default": False, "description": "Transparent background"},
            },
            self._snapshot,
            undoable=False,
        )

        registry.register_command(
            "render.viewport_snapshot",
            "Capture the 3D viewport via OpenGL (much faster than a full render).",
            {"output_path": {"type": "string", "required": True, "description": "Absolute output path"}},
            self._viewport_snapshot,
            undoable=False,
        )

        registry.register_command(
            "render.set_engine",
            "Set the scene render engine.",
            {"engine": {"type": "string", "default": "EEVEE",
                        "description": "EEVEE / CYCLES / WORKBENCH (or exact identifier)"}},
            self._set_engine,
        )

        registry.register_command(
            "render.set_resolution",
            "Set the scene render resolution.",
            {
                "width": {"type": "int", "default": 1920, "description": "Width in pixels"},
                "height": {"type": "int", "default": 1080, "description": "Height in pixels"},
                "percentage": {"type": "int", "default": 100, "description": "Resolution scale 1~100"},
            },
            self._set_resolution,
        )

    # ── handlers ───────────────────────────────────────────────

    def _snapshot(self, p: dict) -> dict:
        path = self.ctx.prepare_output_path(p["output_path"])
        scene = self.ctx.scene
        render = scene.render
        engine = self.ctx.resolve_render_engine(p["engine"]) if p.get("engine") else render.engine
        file_format = self.ctx.image_format_for(path)

        overrides: list[tuple[Any, str, Any]] = [
            (render, "engine", engine),
            (render, "resolution_x", p["width"]),
            (render, "resolution_y", p["height"]),
            (render, "resolution_percentage", 100),
            (render, "filepath", path),
            (render, "film_transparent", p["transparent"]),
            (render.image_settings, "file_format", file_format),
        ]
        if p["transparent"] and file_format in ("PNG", "OPEN_EXR", "TIFF", "WEBP"):
            overrides.append((render.image_settings, "color_mode", "RGBA"))
        if engine == "CYCLES":
            overrides.append((scene.cycles, "samples", p["samples"]))
        elif hasattr(scene, "eevee"):
            overrides.append((scene.eevee, "taa_render_samples", p["samples"]))

        with _temporary_settings(overrides):
            with self.ctx.ops_context():
                bpy.ops.render.render(write_still=True)

        return {
            **self.ctx.file_info(path),
            "resolution": f"{p['width']}x{p['height']}",
            "engine": engine,
            "samples": p["samples"],
            "camera": scene.camera.name if scene.camera else None,
        }

    def _viewport_snapshot(self, p: dict) -> dict:
        path = self.ctx.prepare_output_path(p["output_path"])
        render = self.ctx.scene.render
        overrides = [
            (render, "filepath", path),
            (render.image_settings, "file_format", self.ctx.image_format_for(path)),
        ]
        with _temporary_settings(overrides):
            with self.ctx.ops_context(require_view3d=True):
                bpy.ops.render.opengl(write_still=True)
        return {**self.ctx.file_info(path), "type": "viewport_snapshot"}

    def _set_engine(self, p: dict) -> dict:
        render = self.ctx.scene.render
        render.engine = self.ctx.resolve_render_engine(p["engine"])
        return {"engine": render.engine}

    def _set_resolution(self, p: dict) -> dict:
        render = self.ctx.scene.render
        render.resolution_x = p["width"]
        render.resolution_y = p["height"]
        render.resolution_percentage = max(1, min(p["percentage"], 100))
        return {
            "width": render.resolution_x,
            "height": render.resolution_y,
            "percentage": render.resolution_percentage,
        }


@contextlib.contextmanager
def _temporary_settings(overrides: list[tuple[Any, str, Any]]) -> Iterator[None]:
    """临时修改一组 RNA 属性，退出时按逆序恢复原值（即使渲染失败）。"""
    originals: list[tuple[Any, str, Any]] = []
    try:
        for owner, attr, value in overrides:
            originals.append((owner, attr, getattr(owner, attr)))
            setattr(owner, attr, value)
        yield
    finally:
        for owner, attr, value in reversed(originals):
            try:
                setattr(owner, attr, value)
            except (TypeError, ValueError, AttributeError):
                pass
