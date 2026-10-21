"""渲染命令处理器。

提供完整渲染输出、视口快照、渲染引擎与分辨率设置等命令。
"""

from __future__ import annotations

import os

import bpy

from blender_mcp.shared.errors import BlenderMCPError, ErrorCode
from ..dispatcher import command


@command("render.snapshot")
def snapshot(
    output_path: str,
    width: int = 1920,
    height: int = 1080,
    samples: int = 64,
    engine: str | None = None,
    transparent: bool = False,
) -> dict:
    """将当前场景渲染为图片文件。

    Args:
        output_path: 保存渲染图片的绝对路径（例如 ``/tmp/render.png``）。
        width: 渲染宽度，单位像素。
        height: 渲染高度，单位像素。
        samples: 渲染采样数（越高质量越好，速度越慢）。
        engine: 渲染引擎：``BLENDER_EEVEE_NEXT``、``CYCLES`` 或
            ``BLENDER_WORKBENCH``。``None`` 保持当前设置。
        transparent: 若为 ``True``，使用透明背景渲染。

    Returns:
        包含渲染结果详情的字典。
    """
    scene = bpy.context.scene
    # 保存原始设置
    orig_x = scene.render.resolution_x
    orig_y = scene.render.resolution_y
    orig_path = scene.render.filepath
    orig_format = scene.render.image_settings.file_format
    orig_alpha = scene.render.film_transparent

    try:
        scene.render.resolution_x = width
        scene.render.resolution_y = height
        scene.render.filepath = output_path
        scene.render.film_transparent = transparent

        # 根据扩展名确定文件格式
        ext = os.path.splitext(output_path)[1].lower()
        format_map: dict[str, str] = {
            ".png": "PNG", ".jpg": "JPEG", ".jpeg": "JPEG",
            ".bmp": "BMP", ".tiff": "TIFF", ".tif": "TIFF",
            ".exr": "OPEN_EXR", ".hdr": "HDR",
        }
        scene.render.image_settings.file_format = format_map.get(ext, "PNG")
        if transparent and ext == ".png":
            scene.render.image_settings.color_mode = "RGBA"

        if engine:
            scene.render.engine = engine.upper()

        # 设置采样数
        if scene.render.engine == "CYCLES":
            scene.cycles.samples = samples
        elif hasattr(scene, "eevee"):
            scene.eevee.taa_render_samples = samples

        bpy.ops.render.render(write_still=True)

        file_size = os.path.getsize(output_path) if os.path.exists(output_path) else 0
        return {
            "status": "success",
            "output_path": output_path,
            "resolution": f"{width}x{height}",
            "engine": scene.render.engine,
            "samples": samples,
            "file_size_kb": round(file_size / 1024, 1),
        }
    finally:
        # 恢复原始设置
        scene.render.resolution_x = orig_x
        scene.render.resolution_y = orig_y
        scene.render.filepath = orig_path
        scene.render.image_settings.file_format = orig_format
        scene.render.film_transparent = orig_alpha


@command("render.set_engine")
def set_engine(engine: str = "BLENDER_EEVEE_NEXT") -> dict:
    """设置渲染引擎。

    Args:
        engine: ``BLENDER_EEVEE_NEXT``、``CYCLES`` 或 ``BLENDER_WORKBENCH``。

    Returns:
        包含当前活动 *engine* 名称的字典。
    """
    bpy.context.scene.render.engine = engine.upper()
    return {"engine": bpy.context.scene.render.engine}


@command("render.set_resolution")
def set_resolution(
    width: int = 1920,
    height: int = 1080,
    percentage: int = 100,
) -> dict:
    """设置渲染分辨率。

    Args:
        width: 宽度，单位像素。
        height: 高度，单位像素。
        percentage: 分辨率百分比（1–100）。

    Returns:
        包含 *width*、*height* 和 *percentage* 的字典。
    """
    scene = bpy.context.scene
    scene.render.resolution_x = width
    scene.render.resolution_y = height
    scene.render.resolution_percentage = percentage
    return {"width": width, "height": height, "percentage": percentage}


@command("render.viewport_snapshot")
def viewport_snapshot(output_path: str) -> dict:
    """快速截取 OpenGL 视口快照（比完整渲染快得多）。

    Args:
        output_path: 保存图片的绝对路径。

    Returns:
        包含 *status*、*output_path*、*file_size_kb* 和 *type* 的字典。

    Raises:
        BlenderMCPError: 若找不到 3D 视口则抛出 ``INVALID_MODE``。
    """
    # 查找 3D 视口
    for area in bpy.context.screen.areas:
        if area.type == "VIEW_3D":
            for region in area.regions:
                if region.type == "WINDOW":
                    override = bpy.context.copy()
                    override["area"] = area
                    override["region"] = region
                    bpy.context.scene.render.filepath = output_path
                    ext = os.path.splitext(output_path)[1].lower()
                    if ext == ".png":
                        bpy.context.scene.render.image_settings.file_format = "PNG"
                    with bpy.context.temp_override(**override):
                        bpy.ops.render.opengl(write_still=True)
                    file_size = (
                        os.path.getsize(output_path)
                        if os.path.exists(output_path)
                        else 0
                    )
                    return {
                        "status": "success",
                        "output_path": output_path,
                        "file_size_kb": round(file_size / 1024, 1),
                        "type": "viewport_snapshot",
                    }

    raise BlenderMCPError(
        ErrorCode.INVALID_MODE,
        "No 3D viewport found for snapshot",
    )
