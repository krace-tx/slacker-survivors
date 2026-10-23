# Blender MCP

面向游戏资产管线的 Blender MCP Server，为《摸鱼幸存者 (Slacker Survivors)》Godot 项目量身打造。
架构风格与 `addons/godot_mcp` 完全对齐。

## 架构设计

采用与 Godot MCP 一致的分层解耦架构：

```
AI Client
   │  MCP (stdio: Tools + Resources)
   ▼
server/main.py ──▶ tools/*_tools.py (ToolGroup) & resources/*_resources.py (ResourceGroup)
   │               └─▶ utils/blender_connection.py (单例 BlenderConnection)
   │  NDJSON over TCP (127.0.0.1:9876, JSON-RPC 2.0 / Legacy 双模)
   ▼
addon/mcp_service.py (编排器，对应 godot_mcp/mcp_server.gd)
   ├── transport/tcp_transport.py    专职非阻塞 TCP 传输层（多客户端，对应 ws_transport.gd）
   ├── rpc/rpc_dispatcher.py         JSON-RPC 2.0 + Legacy 双模路由与 rpc.discover（对应 rpc_dispatcher.gd）
   ├── rpc/rpc_error.py              语义化错误封装（对应 rpc_error.gd）
   ├── registry/command_spec.py      指令契约、类型/枚举校验、默认值回填与 JSON Schema 导出（对应 command_spec.gd）
   ├── registry/command_registry.py  统一指令注册表与别名映射（对应 command_registry.gd）
   ├── blender_context.py            Blender 上下文代理：数据块寻址、算子 temp_override、Undo 记录（对应 editor_context.gd）
   └── modules/*_module.py           自治业务模块（对应 godot_mcp/modules/*.gd）
        ├── system_module.py         system.ping / system.info
        ├── scene_module.py          scene.get_info / list_objects / clear / select / undo / redo
        ├── object_module.py         object.get_info / delete / rename / transform / duplicate / join（含 mesh.* 兼容别名）
        ├── mesh_module.py           mesh.add_primitive / set_smooth
        ├── modifier_module.py       modifier.add / apply / remove / list
        ├── material_module.py       material.create / assign / set_color / list / delete
        ├── camera_module.py         camera.create / look_at / set_active
        ├── light_module.py          light.create / set_world_hdri
        └── render_module.py         render.snapshot / viewport_snapshot / set_engine / set_resolution
```

## 安装

### 1. 安装 Blender Addon

在 Blender 中：

```
Edit → Preferences → Add-ons → Install from Disk... → 选择 addons/blender_mcp 目录（或打包为 zip）
```

启用 **Development: Blender MCP Server** 插件。

### 2. 安装 MCP Server

```bash
cd addons/blender_mcp
python -m venv .venv
# Windows
.venv\Scripts\pip install -e .
# macOS / Linux
.venv/bin/pip install -e .
```

### 3. 配置 AI Client

在 `~/.gemini/config/mcp_config.json` 中添加：

```json
{
  "mcpServers": {
    "blender": {
      "command": "D:/code/GodotProject/slacker-survivors/addons/blender_mcp/.venv/Scripts/blender-mcp.exe",
      "args": ["--port", "9876"]
    }
  }
}
```

## 使用

1. 打开 Blender，在 3D 视口按 `N` 打开侧边栏 → `MCP` 标签 → 点击 `Start Server`
2. 在 AI 对话中即可调用 Blender Tools 与 Resources（支持 `rpc.discover` 自省与 `Ctrl+Z` 逐步撤销）
