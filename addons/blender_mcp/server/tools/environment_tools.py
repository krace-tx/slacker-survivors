"""相机、灯光、渲染相关的 MCP Tool 定义。

提供场景环境设置：相机创建与朝向、灯光创建、
渲染快照和渲染引擎切换。
"""
from __future__ import annotations

from mcp.server.mcpserver import MCPServer

from ..bridge import BlenderBridge
from ._fmt import fmt


def register_environment_tools(mcp: MCPServer, bridge: BlenderBridge) -> None:
    """注册所有相机、灯光、渲染相关的 MCP Tools。

    Args:
        mcp: MCP 服务器实例。
        bridge: 与 Blender Addon 通信的 TCP 桥接客户端。
    """

    # ------------------------------------------------------------------
    # 相机
    # ------------------------------------------------------------------

    @mcp.tool()
    async def blender_create_camera(
        name: str = "Camera",
        location: list[float] = [0.0, 0.0, 0.0],  # noqa: B006
        rotation: list[float] = [0.0, 0.0, 0.0],  # noqa: B006
        lens: float = 50.0,
    ) -> str:
        """Create a camera in the scene.

        Args:
            name: Camera name.
            location: [x, y, z] position.
            rotation: [rx, ry, rz] rotation in radians.
            lens: Focal length in mm.
        """
        result = await bridge.send_command(
            "camera.create",
            {
                "name": name,
                "location": location,
                "rotation": rotation,
                "lens": lens,
            },
        )
        return fmt("Create Camera", result)

    @mcp.tool()
    async def blender_camera_look_at(camera_name: str, target: list[float]) -> str:
        """Point a camera at a target location.

        Args:
            camera_name: Name of the camera.
            target: [x, y, z] point to look at.
        """
        result = await bridge.send_command(
            "camera.look_at",
            {"camera_name": camera_name, "target": target},
        )
        return fmt("Camera Look At", result)

    # ------------------------------------------------------------------
    # 灯光
    # ------------------------------------------------------------------

    @mcp.tool()
    async def blender_create_light(
        name: str = "Light",
        type: str = "POINT",
        location: list[float] = [0.0, 0.0, 0.0],  # noqa: B006
        energy: float = 1000.0,
        color: list[float] = [1.0, 1.0, 1.0],  # noqa: B006
    ) -> str:
        """Create a light source.

        Args:
            name: Light name.
            type: POINT, SUN, SPOT, or AREA.
            location: [x, y, z] position.
            energy: Light power in watts.
            color: [r, g, b] light color.
        """
        result = await bridge.send_command(
            "light.create",
            {
                "name": name,
                "type": type,
                "location": location,
                "energy": energy,
                "color": color,
            },
        )
        return fmt("Create Light", result)

    # ------------------------------------------------------------------
    # 渲染
    # ------------------------------------------------------------------

    @mcp.tool()
    async def blender_render_snapshot(
        output_path: str,
        width: int = 1920,
        height: int = 1080,
        samples: int = 64,
        engine: str = "",
        transparent: bool = False,
    ) -> str:
        """Render the current scene to an image file.

        Args:
            output_path: Absolute path to save the image (e.g. /tmp/render.png).
            width: Width in pixels.
            height: Height in pixels.
            samples: Render samples (higher = better quality).
            engine: Render engine: BLENDER_EEVEE_NEXT, CYCLES, BLENDER_WORKBENCH. Empty keeps current.
            transparent: If true, render with transparent background.
        """
        params: dict = {
            "output_path": output_path,
            "width": width,
            "height": height,
            "samples": samples,
            "transparent": transparent,
        }
        if engine:
            params["engine"] = engine
        result = await bridge.send_command("render.snapshot", params)
        return fmt("Render", result)

    @mcp.tool()
    async def blender_set_render_engine(engine: str = "BLENDER_EEVEE_NEXT") -> str:
        """Set the render engine.

        Args:
            engine: BLENDER_EEVEE_NEXT, CYCLES, or BLENDER_WORKBENCH.
        """
        result = await bridge.send_command(
            "render.set_engine", {"engine": engine}
        )
        return fmt("Render Engine", result)
