import bpy
import sys
import os

# 将父目录加入 import 路径，以便导入 shared 模块
# 作为 Blender 插件安装时，addon 文件夹位于 Blender 的 addons 目录下
addon_dir = os.path.dirname(os.path.abspath(__file__))
parent_dir = os.path.dirname(addon_dir)
if parent_dir not in sys.path:
    sys.path.insert(0, parent_dir)

from .server import AddonSocketServer

bl_info = {
    "name": "Blender MCP Server",
    "author": "BabyRun Team",
    "version": (0, 1, 0),
    "blender": (4, 0, 0),
    "location": "View3D > Sidebar > MCP",
    "description": "MCP bridge server for AI-assisted 3D modeling",
    "category": "Development",
}

# 全局服务器实例
_server: AddonSocketServer | None = None


class BLENDERMCP_PT_panel(bpy.types.Panel):
    bl_label = "MCP Server"
    bl_idname = "BLENDERMCP_PT_panel"
    bl_space_type = 'VIEW_3D'
    bl_region_type = 'UI'
    bl_category = 'MCP'

    def draw(self, context):
        layout = self.layout
        scene = context.scene

        row = layout.row()
        row.prop(scene, "blender_mcp_port", text="Port")

        row = layout.row()
        if _server and _server.is_running:
            row.operator("blender_mcp.toggle_server", text="Stop Server", icon='PAUSE')
            layout.label(text=f"Status: Running on port {scene.blender_mcp_port}", icon='CHECKMARK')
            if _server.client_connected:
                layout.label(text="Client: Connected", icon='LINKED')
            else:
                layout.label(text="Client: Waiting...", icon='UNLINKED')
        else:
            row.operator("blender_mcp.toggle_server", text="Start Server", icon='PLAY')
            layout.label(text="Status: Stopped", icon='X')


class BLENDERMCP_OT_toggle_server(bpy.types.Operator):
    bl_idname = "blender_mcp.toggle_server"
    bl_label = "Toggle MCP Server"
    bl_description = "Start or stop the MCP bridge server"

    def execute(self, context):
        global _server
        if _server and _server.is_running:
            _server.stop()
            _server = None
            self.report({'INFO'}, "MCP Server stopped")
        else:
            port = context.scene.blender_mcp_port
            _server = AddonSocketServer(port=port)
            _server.start()
            self.report({'INFO'}, f"MCP Server started on port {port}")
        return {'FINISHED'}


def register():
    bpy.types.Scene.blender_mcp_port = bpy.props.IntProperty(
        name="Port",
        default=9876,
        min=1024,
        max=65535
    )
    bpy.utils.register_class(BLENDERMCP_PT_panel)
    bpy.utils.register_class(BLENDERMCP_OT_toggle_server)


def unregister():
    global _server
    if _server and _server.is_running:
        _server.stop()
        _server = None
    bpy.utils.unregister_class(BLENDERMCP_OT_toggle_server)
    bpy.utils.unregister_class(BLENDERMCP_PT_panel)
    del bpy.types.Scene.blender_mcp_port
