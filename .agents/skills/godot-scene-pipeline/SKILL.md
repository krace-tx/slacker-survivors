---
name: godot-scene-pipeline
description: >-
  Godot 4 声明式场景架构、Godot MCP 稳定装配与多模态视觉验收管线。在创建、修改或重构任何 `.tscn` 场景、
  搭建 2D 响应式 UI 界面/弹窗/HUD、组装 2D/3D 游戏世界舞台、拆分可复用 Prefab 预制体组件，或排查界面布局错位与节点耦合前自动触发。
  强制通过 Godot MCP（编辑器实时通道）或引擎原生 PackedScene 构建器生成 `.tscn`，严禁手搓脆弱巨型 `.tscn` 文本或在 `_ready()` 中靠 `.new()` 堆砌静态节点树，并强制执行「Spec ➔ Decompose ➔ Assemble ➔ Audit ➔ Render ➔ Deliver」六步闭环。
---

# Godot 4 声明式场景构建与视觉验收管线 (Godot Scene Pipeline)

> **核心使命**：将 AI 搭建 Godot 场景从“手写易碎 `.tscn` 文本 / `_ready()` 命令式拼树”彻底升级为 **“声明式预制体分层 + Godot MCP 引擎原生序列化 + Headless 结构与多模态视觉双门禁”** 的确定性工程管线。

---

## 1. 三大技能协同边界

| 技能 | 核心职责边界 | 交叉移交时机 |
| :--- | :--- | :--- |
| **[`framework-aware`](../framework-aware/SKILL.md)** | 模块分层、MSVP/MES 切片、`BaseScene`/`BaseDialog` 继承、`game_scenes.gd` 路由契约、`R01~R16` 门禁 | 涉及正式目录落点（`src/game/`、`src/assets/`）与业务代码编写时同步遵守 |
| **[`blender-pipeline`](../blender-pipeline/SKILL.md)** | 单件 3D 资产（角色/建筑/道具）程序化建模、PBR 材质、骨骼动画与 `.glb` 导出 | 3D 舞台缺少目标 `.glb` 模型资产时，先移交生产资产再回本管线装配舞台 |
| **`godot-scene-pipeline`（本技能）** | `.tscn` 预制体拆解、Godot MCP 确定性节点编排、UI 响应式布局、2D/3D 舞台组装与真实渲染帧验收 | 任何涉及 `.tscn` 创建/修改、界面美化与关卡布景任务全程主导 |

---

## 2. `.tscn` 稳定生成双通道铁律（MCP-First）

**严禁直接手写/正则硬改包含复杂 `SubResource`、`ExtResource` 或深层嵌套节点的 `.tscn` 纯文本**。所有 `.tscn` 变更必须经由 Godot 引擎原生 `PackedScene` 序列化器落盘：

1. **首选通道：Godot MCP 实时编辑器通道（`ws://127.0.0.1:9080`）**
   - 先探测在线状态：`python .agents/skills/godot-scene-pipeline/scripts/mcp_scene_cli.py status`（若 IDE 已直接挂载 `GodotMCP` MCP 工具亦可直接调用对应 Tool）。
   - 在线时（`online: true`），通过 Godot MCP 原子指令（`scene.create`、`node.create`、`node.instantiate_scene`、`ui.set_anchor_preset`、`ui.set_size_flags`、`ui.set_theme_override`、`node.set_unique_name`、`script.attach`、`signal.connect`、`scene.save`）或 `mcp_scene_cli.py apply <blueprint.json>` 在编辑器内实时构建并保存 `.tscn`，自动享有完整 `Undo/Redo` 历史与零语法损坏保障。
2. **离线兜底通道：Headless `PackedScene` 蓝图构建器**
   - 当开发机未打开 Godot Editor（`online: false`）时，将场景结构编写为声明式 JSON Blueprint，执行 `python .agents/skills/godot-scene-pipeline/scripts/mcp_scene_cli.py apply <blueprint.json>`。
   - CLI 会自动降级调用 [`headless_blueprint_builder.gd`](./scripts/headless_blueprint_builder.gd)，在引擎进程内调用 C++ `PackedScene.pack()` + `ResourceSaver.save()` 生成 100% 合法的 `.tscn`（自动生成 `unique_id`、`layout_mode` 与 `SubResource` ID）。

---

## 3. 渐进式披露知识库路由（按需读取）

在执行具体类型场景任务前，**必须按需读取**对应参考分册，严禁凭直觉盲写：

| 任务场景 | 必读分册 |
| :--- | :--- |
| 使用 Godot MCP 指令集、JSON Blueprint 批量构建或排障 | [`references/godot_mcp_workflow.md`](./references/godot_mcp_workflow.md) |
| 拆分 `1 .tscn + N .gd` 预制体层级、`%UniqueName`、`@export` 与路由注册 | [`references/prefab_architecture_and_contracts.md`](./references/prefab_architecture_and_contracts.md) |
| 设计 2D UI 界面、弹窗、响应式锚点/`size_flags`、暗黑极简色彩字阶与留白 | [`references/ui_layout_and_design_system.md`](./references/ui_layout_and_design_system.md) |
| 组装 2D/3D 世界舞台、相机灯光、碰撞层与 `.glb` 预制体接地排布 | [`references/world_stage_2d_3d.md`](./references/world_stage_2d_3d.md) |
| 查看端到端 UI 组件/复合舞台与 3D 关卡 Blueprint 实战模板 | [`examples/scene_blueprints.md`](./examples/scene_blueprints.md) |

---

## 4. 强制执行六步闭环工作流

```text
[1. Spec] ➔ [2. Decompose] ➔ [3. Assemble (MCP)] ➔ [4. Audit] ➔ [5. Render & Read] ➔ [6. Deliver]
                                      ▲                                  │
                                      └─────── 发现错位/溢出/丑陋立即返工 ────┘
```

### Step 1 · Spec（空间与交互契约对齐）
- 确认画布基准：项目全局基准为 `1920x1080`（`stretch/mode = "canvas_items"`，`aspect = "expand"`）。
- 明确视觉焦点、留白层级、静态占位默认值（编辑器零运行可见）以及视图向 Presenter 暴露的公开方法与上行 `signal`。

### Step 2 · Decompose（声明式预制体原子拆解）
- **单文件节点预算封顶**：叶组件 ≤ 15 节点、区域面板 ≤ 30 节点、顶层舞台 ≤ 25 节点（单个 `.tscn` 本地节点严禁超过 40 个）。
- 凡出现 ≥ 2 次的同类结构（槽位卡、属性行、列表项、3D 路灯/掩体组）**必须**拆分为独立 `component/<unit>/<unit>.tscn`，由父场景通过 `instantiate_scene` 组合。

### Step 3 · Assemble（Godot MCP 声明式装配）
- **自底向上构建**：先构建并保存子组件 `.tscn` 及配套 `.gd`，再在父面板/顶层舞台中调用 `instantiate_scene` 挂载子预制体。
- **零运行时建树铁律**：严禁在视图 `.gd` 的 `_ready()` 中调用 `VBoxContainer.new()` / `PanelContainer.new()` 等搭建静态布局骨架；脚本仅允许对动态数量数据执行 `PackedScene.instantiate()`。
- **寻址解耦**：子节点访问统一开启 `unique_name_in_owner = true` 并使用 `%NodeName` 或 `@export`，严禁硬编码 `$A/B/C` 深层路径。

### Step 4 · Audit（Headless 结构树体检门禁）
运行结构审计器校验零断链、零 `0x0` 交互控件塌陷、零视口溢出、零违规 `.new()` 建树：
```powershell
& "D:/software/Godot/Godot_v4.7.1-stable_win64.exe/Godot_v4.7.1-stable_win64_console.exe" --headless --path . -s .agents/skills/godot-scene-pipeline/scripts/audit_scene.gd -- --dir=res://src/<target_view_dir>
```

### Step 5 · Render & Read（多模态渲染帧自检门禁）
调用预览捕获脚本同时输出 `1920x1080` 与 `1280x720` 真实渲染帧（或通过 MCP `editor-2d`/`editor-3d` 抓取编辑器视口）：
```powershell
python .agents/skills/godot-scene-pipeline/scripts/capture_scene_preview.py --scene res://src/<target_scene>.tscn --out-dir <scratch_dir>/previews --resolutions 1920x1080,1280x720 --audit
```
**必须调用 `read_file` 亲自查看生成的 PNG 截图**，逐项核查：
1. 文字是否被裁切、重叠或对比度过低；
2. 面板内边距（Padding）与间距（Separation）是否呼吸均匀、对齐成线；
3. `1280x720` 紧凑视口下是否发生挤压变形；
4. 3D 资产是否稳固接地（无浮空/穿模）、构图与打光是否主次分明。
> 未通过视觉自检严禁向用户交付，必须通过 Godot MCP 微调属性后重拍确认！

### Step 6 · Deliver（工程合规收口）
- 若新增路由级 `BaseScene` / `BaseDialog` / 共享组件，确认已在 [`game_scenes.gd`](../../../src/game/shared/model/config/game_scenes.gd) 生成强类型常量。
- 运行架构合规门禁 `python .agents/skills/framework-aware/scripts/check_compliance.py` 确保全绿收口。
