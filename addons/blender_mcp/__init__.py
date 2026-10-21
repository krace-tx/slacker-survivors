"""Blender MCP 插件与包入口。"""

bl_info = {
    "name": "Blender MCP Server",
    "author": "BabyRun Team",
    "version": (0, 1, 0),
    "blender": (4, 0, 0),
    "location": "View3D > Sidebar > MCP",
    "description": "MCP bridge server for AI-assisted 3D modeling",
    "category": "Development",
}


def register() -> None:
    """注册 Blender 插件。"""
    from .addon import register as addon_register

    addon_register()


def unregister() -> None:
    """注销 Blender 插件。"""
    from .addon import unregister as addon_unregister

    addon_unregister()
