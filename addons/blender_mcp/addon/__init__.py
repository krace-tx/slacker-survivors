"""Blender 侧插件：UI 面板 + 服务开关。

仅负责 Blender 注册与 UI 交互，所有服务逻辑委托给 ``MCPService`` 编排器。
当在 Blender 进程之外导入 ``blender_mcp.addon.*``（如用于自省或契约测试）时，
``bpy`` 不可用，本模块会静默跳过 UI 类定义而不报错。
"""
from __future__ import annotations

import os
import sys

# 确保无论插件以 blender_mcp/ 根目录还是 addon/ 目录形式安装，都能解析顶层包
_addon_dir = os.path.dirname(os.path.abspath(__file__))
_pkg_dir = os.path.dirname(_addon_dir)
_addons_root = os.path.dirname(_pkg_dir)
for _p in (_addons_root, _pkg_dir):
    if _p and _p not in sys.path:
        sys.path.insert(0, _p)

try:
    import bpy
except ImportError:
    bpy = None  # type: ignore[assignment]

from ..shared.constants import DEFAULT_PORT

bl_info = {
    "name": "Blender MCP Server",
    "author": "BabyRun Team",
    "version": (0, 2, 0),
    "blender": (4, 0, 0),
    "location": "View3D > Sidebar > MCP",
    "description": "MCP bridge server for AI-assisted 3D modeling",
    "category": "Development",
}

# 全局服务实例（插件重载 / 注销时负责释放）
_service = None


def get_service():
    """返回当前运行中的 ``MCPService``（未启动时为 ``None``）。"""
    return _service


if bpy is not None:

    class BLENDERMCP_PT_panel(bpy.types.Panel):
        bl_label = "MCP Server"
        bl_idname = "BLENDERMCP_PT_panel"
        bl_space_type = "VIEW_3D"
        bl_region_type = "UI"
        bl_category = "MCP"

        def draw(self, context):
            layout = self.layout
            running = _service is not None and _service.is_running

            row = layout.row()
            row.enabled = not running
            row.prop(context.window_manager, "blender_mcp_port", text="Port")

            if running:
                layout.operator("blender_mcp.toggle_server", text="Stop Server", icon="PAUSE")
                layout.label(text=f"Running on 127.0.0.1:{_service.port}", icon="CHECKMARK")
                clients = _service.client_count
                if clients:
                    layout.label(text=f"Clients: {clients} connected", icon="LINKED")
                else:
                    layout.label(text="Clients: waiting...", icon="UNLINKED")
                layout.label(text=f"Commands: {len(_service.registry.primary_names())}", icon="CONSOLE")
            else:
                layout.operator("blender_mcp.toggle_server", text="Start Server", icon="PLAY")
                layout.label(text="Status: Stopped", icon="X")

    class BLENDERMCP_OT_toggle_server(bpy.types.Operator):
        bl_idname = "blender_mcp.toggle_server"
        bl_label = "Toggle MCP Server"
        bl_description = "Start or stop the MCP bridge server"

        def execute(self, context):
            global _service
            if _service is not None and _service.is_running:
                _service.stop()
                _service = None
                self.report({"INFO"}, "MCP Server stopped")
                return {"FINISHED"}

            from .mcp_service import MCPService

            port = context.window_manager.blender_mcp_port
            service = MCPService()
            try:
                service.start(port=port)
            except OSError as exc:
                service.stop()
                self.report({"ERROR"}, f"MCP Server failed to start on port {port}: {exc}")
                return {"CANCELLED"}
            _service = service
            self.report({"INFO"}, f"MCP Server started on port {port}")
            return {"FINISHED"}

    _CLASSES = (BLENDERMCP_PT_panel, BLENDERMCP_OT_toggle_server)
else:
    _CLASSES = ()


def register() -> None:
    if bpy is None:
        raise RuntimeError("register() can only be called inside Blender")
    bpy.types.WindowManager.blender_mcp_port = bpy.props.IntProperty(
        name="Port", default=DEFAULT_PORT, min=1024, max=65535,
    )
    for cls in _CLASSES:
        bpy.utils.register_class(cls)


def unregister() -> None:
    global _service
    if _service is not None:
        _service.stop()
        _service = None
    if bpy is None:
        return
    for cls in reversed(_CLASSES):
        bpy.utils.unregister_class(cls)
    del bpy.types.WindowManager.blender_mcp_port
