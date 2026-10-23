"""渲染 Tools：完整渲染、视口快照、渲染引擎与分辨率。"""
from __future__ import annotations

from ..utils import call
from ._group import ToolGroup

render_tools = ToolGroup("render")

# 完整渲染（尤其 CYCLES）可能远超常规指令超时
_RENDER_TIMEOUT = 600.0


@render_tools.tool(read_only=True)
async def blender_render_snapshot(
    output_path: str,
    width: int | None = None,
    height: int | None = None,
    samples: int | None = None,
    engine: str | None = None,
    transparent: bool = False,
) -> str:
    """Render the scene through the active camera to an image file (scene settings are restored afterwards).

    Args:
        output_path: Absolute output path, e.g. D:/tmp/render.png. Format is inferred from the extension.
        width: Width in pixels. Default 1920.
        height: Height in pixels. Default 1080.
        samples: Render samples. Default 64.
        engine: EEVEE, CYCLES or WORKBENCH. Omit to keep the current engine.
        transparent: Render with a transparent background.
    """
    return await call("Render", "render.snapshot", timeout=_RENDER_TIMEOUT, output_path=output_path,
                      width=width, height=height, samples=samples, engine=engine, transparent=transparent)


@render_tools.tool(read_only=True)
async def blender_viewport_snapshot(output_path: str) -> str:
    """Capture the 3D viewport via OpenGL — much faster than a full render, good for quick visual checks.

    Args:
        output_path: Absolute output path, e.g. D:/tmp/viewport.png.
    """
    return await call("Viewport Snapshot", "render.viewport_snapshot", output_path=output_path)


@render_tools.tool(idempotent=True)
async def blender_set_render_engine(engine: str = "EEVEE") -> str:
    """Set the scene render engine.

    Args:
        engine: EEVEE, CYCLES or WORKBENCH (version-specific identifiers like BLENDER_EEVEE_NEXT also work).
    """
    return await call("Render Engine", "render.set_engine", engine=engine)


@render_tools.tool(idempotent=True)
async def blender_set_render_resolution(width: int = 1920, height: int = 1080, percentage: int = 100) -> str:
    """Set the scene render resolution.

    Args:
        width: Width in pixels.
        height: Height in pixels.
        percentage: Resolution scale 1~100.
    """
    return await call("Render Resolution", "render.set_resolution",
                      width=width, height=height, percentage=percentage)
