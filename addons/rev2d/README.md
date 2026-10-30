# Godot 4 Rev2D Addon (`addons/rev2d`)

本插件将 **Rev2D（AI 2D 骨骼绑定 + IK / 摆锤物理 + Spine 4.2 导出器）** 直接内置到 Godot 4 工程 `addons/rev2d/` 中：

- **`plugin.cfg` / `rev2d_plugin.gd`**：Godot 编辑器插件（已在 `project.godot` 默认启用），在顶部菜单 **`项目 (Project) -> 工具 (Tools)`** 下提供：
  1. **`Rev2D: 打开可视化骨骼编辑器 (Web UI)`**：启动内置 `rev2d edit` 服务（`http://127.0.0.1:4777`）并直接打开项目的 `art/spines/` 骨骼模型；
  2. **`Rev2D: 重新构建并导出 Spine 骨骼`**：调用内置 `addons/rev2d/runtime/bin/rev2d.js` 重新校验导出 `art/spines/` 下的骨骼并自动触发 Godot 资源扫描。
- **`runtime/`（含 `.gdignore`）**：完整的已编译 `Rev2D` CLI（`bin/rev2d.js`）、MCP Server（`bin/rev2d.js mcp`）与可视化编辑器运行时；通过 `.gdignore` 隔离，不干扰 Godot 资产导入速度。
