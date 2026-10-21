# Blender MCP

面向游戏资产管线的 Blender MCP Server，为《摸鱼幸存者 (Slacker Survivors)》Godot 项目量身打造。

## 架构

双进程 Bridge 模式：

```
AI Client ←→ MCP Server (stdio) ←→ TCP ←→ Blender Addon (bpy)
```

- **`addon/`**: 安装进 Blender 的插件，提供 TCP Socket 监听与 bpy 命令执行
- **`server/`**: 独立的 MCP Server 进程，桥接 AI 与 Blender
- **`shared/`**: 双端共享的协议定义与常量

## 安装

### 1. 安装 Blender Addon

将 `addon/` 文件夹拷贝到 Blender 的插件目录，或在 Blender 中：

```
Edit → Preferences → Add-ons → Install → 选择 addon/ 文件夹
```

### 2. 安装 MCP Server

```bash
cd addons/blender_mcp
python3 -m venv .venv
.venv/bin/pip install -e .
```

### 3. 配置 AI Client

在 `~/.gemini/config/mcp_config.json` 中添加：

```json
{
  "mcpServers": {
    "blender": {
      "command": "/Users/krace/Code/GodotProject/slacker-survivors/addons/blender_mcp/.venv/bin/blender-mcp",
      "args": ["--port", "9876"]
    }
  }
}
```

## 使用

1. 打开 Blender
2. 按 `N` 键打开侧边栏 → 点击 `MCP` 标签 → 点击 `Start Server`
3. 在 AI 对话中即可使用 Blender 建模工具
