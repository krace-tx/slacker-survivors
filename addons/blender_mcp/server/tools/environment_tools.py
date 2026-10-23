"""相机与灯光 Tools：相机创建 / 朝向 / 激活，光源创建，世界 HDRI。"""
from __future__ import annotations

from ..utils import call
from ._group import ToolGroup

camera_tools = ToolGroup("camera")
light_tools = ToolGroup("light")


# ── 相机 ───────────────────────────────────────────────────────


@camera_tools.tool()
async def blender_create_camera(
    name: str | None = None,
    location: list[float] | None = None,
    rotation: list[float] | None = None,
    lens: float | None = None,
    type: str | None = None,
    ortho_scale: float | None = None,
    look_at: list[float] | None = None,
    set_active: bool = False,
) -> str:
    """Create a camera.

    Args:
        name: Camera name. Default "Camera".
        location: [x, y, z] position.
        rotation: [rx, ry, rz] Euler rotation in radians (ignored if look_at is given).
        lens: Focal length in mm. Default 50.
        type: PERSP (default), ORTHO or PANO.
        ortho_scale: Orthographic scale (ORTHO only).
        look_at: [x, y, z] point to aim the camera at.
        set_active: Make it the scene's render camera.
    """
    return await call("Create Camera", "camera.create", name=name, location=location, rotation=rotation,
                      lens=lens, type=type, ortho_scale=ortho_scale, look_at=look_at, set_active=set_active)


@camera_tools.tool(idempotent=True)
async def blender_camera_look_at(camera_name: str, target: list[float]) -> str:
    """Rotate a camera so it points at a target location.

    Args:
        camera_name: Camera object name.
        target: [x, y, z] point to look at.
    """
    return await call("Camera Look At", "camera.look_at", camera_name=camera_name, target=target)


@camera_tools.tool(idempotent=True)
async def blender_set_active_camera(camera_name: str) -> str:
    """Set the scene's active (render) camera.

    Args:
        camera_name: Camera object name.
    """
    return await call("Active Camera", "camera.set_active", camera_name=camera_name)


# ── 灯光 ───────────────────────────────────────────────────────


@light_tools.tool()
async def blender_create_light(
    name: str | None = None,
    type: str | None = None,
    location: list[float] | None = None,
    rotation: list[float] | None = None,
    energy: float | None = None,
    color: list[float] | None = None,
    radius: float | None = None,
) -> str:
    """Create a light source.

    Args:
        name: Light name. Default "Light".
        type: POINT (default), SUN, SPOT or AREA.
        location: [x, y, z] position.
        rotation: [rx, ry, rz] radians (direction matters for SUN / SPOT / AREA).
        energy: Power in watts. Default 1000. For SUN this is irradiance (typically 1~10).
        color: [r, g, b] in 0~1. Default white.
        radius: Soft shadow radius. Default 0.25.
    """
    return await call("Create Light", "light.create", name=name, type=type, location=location,
                      rotation=rotation, energy=energy, color=color, radius=radius)


@light_tools.tool(idempotent=True)
async def blender_set_world_hdri(hdri_path: str, strength: float | None = None,
                                 rotation_z: float | None = None) -> str:
    """Use an HDRI image (.hdr / .exr) as world environment lighting (replaces the world node tree).

    Args:
        hdri_path: Absolute path to the HDRI file.
        strength: Background strength. Default 1.0.
        rotation_z: Environment rotation around Z in radians. Default 0.
    """
    return await call("World HDRI", "light.set_world_hdri", hdri_path=hdri_path,
                      strength=strength, rotation_z=rotation_z)
