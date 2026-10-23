"""Blender MCP 插件与包入口。

- 在 Blender 中：作为插件包加载，``register`` / ``unregister`` 委托给 ``addon`` 子包。
- 在外部 Python 中：作为 ``blender_mcp`` 包供 ``server`` 子包导入，
  本文件不得在模块顶层导入 ``bpy``。
"""

bl_info = {
    "name": "Blender MCP Server",
    "author": "BabyRun Team",
    "version": (0, 2, 0),
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
