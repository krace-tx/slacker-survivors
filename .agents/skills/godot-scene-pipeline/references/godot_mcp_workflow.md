# Skill Wiki · Godot MCP 场景构建工作流与指令全集 (Godot MCP Workflow)

> 📖 **Wiki 定位**：规范如何通过工程内置的 [`addons/godot_mcp`](../../../../addons/godot_mcp/mcp_server.gd) 插件（`ws://127.0.0.1:9080`）及 [`mcp_scene_cli.py`](../scripts/mcp_scene_cli.py) 稳定、可逆、零损坏地创建和编辑 `.tscn` 场景文件。

---

## 1. 为什么必须走 Godot MCP 编辑 `.tscn`？

Godot 4 的 `.tscn` 格式包含强耦合的头信息与内部状态：
- `[ext_resource type="PackedScene" uid="uid://..." path="res://..." id="1_xxx"]`
- `[sub_resource type="StyleBoxFlat" id="StyleBoxFlat_xxx"]`
- 容器子节点特有的 `layout_mode = 2`、根节点锚点 `anchors_preset = 15`、场景唯一名 `unique_name_in_owner = true` 以及 `owner` 归属链。

LLM 直接用文本工具拼改 `.tscn` 极易造成 **ID 引用悬空、锚点与 `layout_mode` 冲突导致编辑器打不开场景、或节点因缺失 `owner` 在保存时蒸发**。  
通过 **`addons/godot_mcp`** 操作场景树，所有增删改均在引擎内存中经由 `EditorInterface` + `EditorUndoRedoManager` 执行，并最终由引擎 C++ `PackedScene.pack()` + `ResourceSaver.save()` 落盘，**从根源上保证 100% 序列化稳定性且支持编辑器 `Ctrl+Z` 撤销**。

---

## 2. 连接探测与双调用方式

### 方式 A：IDE 已挂载 `GodotMCP` 工具时
直接调用 MCP 工具（如 `create_scene`、`instantiate_scene`、`set_theme_override`、`save_scene`）。

### 方式 B：通过内置零依赖 CLI 直连 `ws://127.0.0.1:9080`
无论 IDE 是否挂载 stdio MCP，只要 Godot 编辑器处于打开状态，均可使用 [`mcp_scene_cli.py`](../scripts/mcp_scene_cli.py) 直接发送 JSON-RPC 2.0 指令：

```powershell
# 1. 探测 Godot Editor MCP 在线状态与当前打开的场景
python .agents/skills/godot-scene-pipeline/scripts/mcp_scene_cli.py status

# 2. 查看当前已注册的全部 RPC 指令契约
python .agents/skills/godot-scene-pipeline/scripts/mcp_scene_cli.py discover

# 3. 修改 addons/godot_mcp 插件脚本后热重载插件
python .agents/skills/godot-scene-pipeline/scripts/mcp_scene_cli.py reload-plugin
```

---

## 3. 核心场景编排指令速查表

| 领域 | RPC 方法名（MCP Tool 别名） | 关键参数 | 用途说明 |
| :--- | :--- | :--- | :--- |
| **场景生命周期** | `scene.create` (`create_scene`) | `path`, `root_node_type`, `root_node_name`, `base_scene_path`, `root_script` | 新建空白场景或基于 `base_scene_path` 创建**继承场景**，支持同时挂载根脚本 |
| | `scene.open` (`open_scene`) | `path` | 在编辑器中切换打开指定 `.tscn` |
| | `scene.save` (`save_scene`) | `path` (可选) | 将当前编辑树通过 `PackedScene.pack` 落盘保存 |
| **节点与预制体** | `node.create` (`create_node`) | `parent_path`, `node_type`, `node_name` | 创建原生引擎节点并自动绑定 `owner` 与 UndoRedo |
| | `node.instantiate_scene` (`instantiate_scene`) | `parent_path`, `scene_path`, `node_name` | **核心**：将子组件 `.tscn` 或 `.glb` 作为预制体实例挂入父节点（生成 `instance=ExtResource(...)`） |
| | `node.set_unique_name` (`set_unique_name`) | `node_path`, `enabled` | 开启 `%UniqueName`（`unique_name_in_owner = true`），此后可直接用 `%Name` 寻址 |
| | `node.move` (`move_node`) | `node_path`, `new_parent_path`, `index` | 调整容器内子节点排列顺序或跨父节点移动 |
| | `node.update_property` (`update_node_property`) | `node_path`, `property`, `value` | 强类型安全属性更新（自动识别目标属性类型并加载 `"res://..."` 资源、解析 `"#RRGGBB"` 颜色、`Vector2`/`Vector3`） |
| | `node.get_tree` (`get_scene_tree`) | `root_path`, `max_depth` | 单次请求导出完整节点树层级、脚本、预制体来源与 `Control` 矩形 |
| **UI 布局与样式** | `ui.set_anchor_preset` (`set_anchor_preset`) | `node_path`, `preset`, `keep_offsets` | 设置锚点预设（`full_rect`, `center`, `top_wide`, `bottom_wide` 等） |
| | `ui.set_size_flags` (`set_size_flags`) | `node_path`, `horizontal`, `vertical` | 设置容器尺寸标志（`fill`, `expand`, `expand_fill`, `shrink_center`, `shrink_end`） |
| | `ui.set_theme_override` (`set_theme_override`) | `node_path`, `override_type`, `name`, `value` | 一键配置 `constant`、`font_size`、`color` 或 `stylebox`（支持 `"res://...tres"` 或内联 `StyleBoxFlat` 字典） |
| **脚本与信号** | `script.attach` (`attach_script`) | `node_path`, `script_path` | 将已编写好的 `.gd` 脚本安全挂载到节点（**不覆盖原脚本内容**） |
| | `signal.connect` (`connect_signal`) | `source_node`, `signal_name`, `target_node`, `method_name`, `persist` | 建立持久化信号连接（`CONNECT_PERSIST`） |
| **视口视觉捕获** | `viewport.capture_2d` / `capture_3d` / `capture_node` | `save_path`, `return_base64` | 直接抓取编辑器 2D/3D 视口或单控件局部截图 |

---

## 4. 声明式 JSON Blueprint 一键构建模式（推荐新建场景使用）

当新建包含 5~30 个节点的完整组件或舞台时，逐条手敲 40 次单步 RPC 耗时较长。可将场景树写成一份结构清晰的 **JSON Blueprint**（存放于对话 `<scratch_dir>/`），交由 `mcp_scene_cli.py apply` 一次性编排落盘：

```powershell
python .agents/skills/godot-scene-pipeline/scripts/mcp_scene_cli.py apply <scratch_dir>/card_blueprint.json
```

### 双模无缝自适应机制
- **编辑器开启时（`ws://127.0.0.1:9080` 在线）**：`apply` 自动在当前编辑器中依次执行 `scene.create` ➔ 递归 `node.create` / `node.instantiate_scene` ➔ 布局与主题设置 ➔ `signal.connect` ➔ `scene.save`，用户在编辑器视口中可立即看到生成结果并随时 `Ctrl+Z`。
- **编辑器关闭时（CI 或纯命令行环境）**：`apply` 自动无缝切换至 [`headless_blueprint_builder.gd`](../scripts/headless_blueprint_builder.gd)，调用 Godot 引擎原生 `PackedScene.pack()` 生成完全一致的 `.tscn`。

### Blueprint 字段契约速览

```json
{
  "scene_path": "res://src/test/demo/view/component/item/demo_item_card.tscn",
  "base_scene_path": "",
  "root": {
    "type": "PanelContainer",
    "name": "DemoItemCard",
    "script": "res://src/test/demo/view/component/item/demo_item_card.gd",
    "properties": {
      "custom_minimum_size": {"x": 88, "y": 88}
    },
    "theme_overrides": {
      "stylebox": {
        "panel": {
          "bg_color": "#0f172a",
          "border_color": "#1e293b",
          "border_width": 1,
          "corner_radius": 10,
          "content_margin": [10, 8, 10, 8]
        }
      }
    },
    "children": [
      {
        "type": "VBoxContainer",
        "name": "ContentBox",
        "unique_name": true,
        "theme_overrides": {"constant": {"separation": 6}},
        "children": [
          {
            "instance": "res://src/test/demo/view/component/art/demo_icon.tscn",
            "name": "IconView",
            "unique_name": true,
            "size_flags": {"horizontal": "shrink_center", "vertical": "expand_fill"}
          },
          {
            "type": "Label",
            "name": "CountLabel",
            "unique_name": true,
            "properties": {"text": "x12", "horizontal_alignment": 2},
            "theme_overrides": {
              "font_size": {"font_size": 12},
              "color": {"font_color": "#cbd5e1"}
            }
          }
        ]
      }
    ]
  },
  "signals": []
}
```

---

## 5. 修改既有 `.tscn` 场景的黄金操作守则

对已有 `.tscn` 进行增量改版时，**严禁使用 `apply` 整文件重建覆盖已有业务配置**，必须使用细粒度增量指令：
1. `call scene.open --params '{"path": "res://..."}' ` 打开目标场景；
2. `call node.get_tree --params '{"max_depth": 6}'` 读取真实节点树路径与现有属性；
3. 按需执行 `node.create` / `node.instantiate_scene` / `node.move` / `ui.set_theme_override` / `node.update_property`；
4. `call scene.save` 落盘，随后立即执行 `audit_scene.gd` 与 `capture_scene_preview.py` 验证。
