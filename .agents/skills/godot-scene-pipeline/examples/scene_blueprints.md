# Skill Wiki · 端到端场景构建蓝图样板集 (Scene Blueprint Examples)

> 📖 **使用指南**：新建 `.tscn` 组件或舞台时，推荐按**自底向上（叶组件 ➔ 区域面板 ➔ 顶层舞台）**顺序在 `<scratch_dir>/` 编写蓝图并通过 `mcp_scene_cli.py apply` 执行，由 Godot MCP（或离线 `PackedScene` 构建器）生成原生 `.tscn`。

---

## 样板 1：声明式 UI 叶组件 + 复合舞台组装

### 1.1 先构建叶组件（`stat_pill.tscn`）
```json
{
  "scene_path": "res://src/test/sample/view/component/pill/stat_pill.tscn",
  "root": {
    "type": "PanelContainer",
    "name": "StatPill",
    "script": "res://src/test/sample/view/component/pill/stat_pill.gd",
    "properties": {
      "custom_minimum_size": {"x": 108, "y": 34}
    },
    "theme_overrides": {
      "stylebox": {
        "panel": {
          "bg_color": "#0d1320",
          "border_color": "#1f2937",
          "border_width": 1,
          "corner_radius": 17,
          "content_margin": [12, 4, 12, 4]
        }
      }
    },
    "children": [
      {
        "type": "HBoxContainer",
        "name": "Row",
        "theme_overrides": {"constant": {"separation": 6}},
        "children": [
          {
            "type": "Label",
            "name": "KeyLabel",
            "unique_name": true,
            "properties": {"text": "ATK"},
            "theme_overrides": {
              "font_size": {"font_size": 12},
              "color": {"font_color": "#94a3b8"}
            }
          },
          {
            "type": "Label",
            "name": "ValueLabel",
            "unique_name": true,
            "size_flags": {"horizontal": "expand_fill"},
            "properties": {"text": "120", "horizontal_alignment": 2},
            "theme_overrides": {
              "font_size": {"font_size": 13},
              "color": {"font_color": "#f1f5f9"}
            }
          }
        ]
      }
    ]
  }
}
```

### 1.2 再在父面板中通过 `instance` 组装子预制体并绑定持久化信号
```json
{
  "scene_path": "res://src/test/sample/view/component/header/sample_header.tscn",
  "root": {
    "type": "PanelContainer",
    "name": "SampleHeader",
    "script": "res://src/test/sample/view/component/header/sample_header.gd",
    "anchor_preset": "top_wide",
    "theme_overrides": {
      "stylebox": {
        "panel": {
          "bg_color": "#111827",
          "border_color": "#1f2937",
          "border_width": 1,
          "corner_radius": 12,
          "content_margin": [20, 12, 20, 12]
        }
      }
    },
    "children": [
      {
        "type": "HBoxContainer",
        "name": "BarRow",
        "theme_overrides": {"constant": {"separation": 12}},
        "children": [
          {
            "type": "Label",
            "name": "TitleLabel",
            "unique_name": true,
            "properties": {"text": "CHARACTER LOADOUT"},
            "theme_overrides": {
              "font_size": {"font_size": 16},
              "color": {"font_color": "#f8fafc"}
            }
          },
          {
            "type": "Control",
            "name": "Spacer",
            "size_flags": {"horizontal": "expand_fill"}
          },
          {
            "instance": "res://src/test/sample/view/component/pill/stat_pill.tscn",
            "name": "AtkPill",
            "unique_name": true
          },
          {
            "type": "Button",
            "name": "ResetButton",
            "unique_name": true,
            "properties": {
              "text": "重置",
              "custom_minimum_size": {"x": 76, "y": 34}
            }
          }
        ]
      }
    ]
  },
  "signals": [
    {
      "source": "%ResetButton",
      "signal": "pressed",
      "target": ".",
      "method": "_on_reset_pressed"
    }
  ]
}
```

---

## 样板 2：3D 游戏舞台 + HUD 覆盖层蓝图

```json
{
  "scene_path": "res://src/test/arena_3d/view/scene/arena/arena_stage_scene.tscn",
  "root": {
    "type": "Node",
    "name": "ArenaStageScene",
    "script": "res://src/test/arena_3d/view/scene/arena/arena_stage_scene.gd",
    "children": [
      {
        "type": "Node3D",
        "name": "World3D",
        "unique_name": true,
        "children": [
          {
            "type": "Node3D",
            "name": "EnvironmentRig",
            "children": [
              {
                "type": "DirectionalLight3D",
                "name": "SunLight",
                "properties": {
                  "rotation_degrees": {"x": -52.0, "y": 35.0, "z": 0.0},
                  "shadow_enabled": true,
                  "light_energy": 1.15
                }
              }
            ]
          },
          {
            "type": "Camera3D",
            "name": "MainCamera",
            "unique_name": true,
            "properties": {
              "position": {"x": 0.0, "y": 9.5, "z": 11.0},
              "rotation_degrees": {"x": -40.0, "y": 0.0, "z": 0.0},
              "current": true,
              "fov": 50.0
            }
          },
          {
            "type": "Node3D",
            "name": "StaticGeometry",
            "children": [
              {
                "instance": "res://src/test/arena_3d/assets/models/mdl_arena_3d_floor.glb",
                "name": "ArenaFloor",
                "properties": {
                  "position": {"x": 0.0, "y": 0.0, "z": 0.0}
                }
              }
            ]
          },
          {
            "type": "Node3D",
            "name": "Actors",
            "unique_name": true
          }
        ]
      },
      {
        "type": "CanvasLayer",
        "name": "HudLayer",
        "properties": {"layer": 10},
        "children": [
          {
            "instance": "res://src/test/sample/view/component/header/sample_header.tscn",
            "name": "TopHud",
            "unique_name": true
          }
        ]
      }
    ]
  }
}
```

---

## 样板 3：标准执行与验收四连指令

```powershell
# 1. 构建组件与舞台（优先走在线 Godot MCP，离线自动走原生 PackedScene）
python .agents/skills/godot-scene-pipeline/scripts/mcp_scene_cli.py apply <scratch_dir>/blueprint.json

# 2. 结构门禁 + 双分辨率渲染帧捕获
python .agents/skills/godot-scene-pipeline/scripts/capture_scene_preview.py `
  --scene res://src/test/inventory/inventory_test.tscn `
  --out-dir <scratch_dir>/previews `
  --resolutions 1920x1080,1280x720 `
  --audit

# 3. Agent 使用 read_file 读取预览 PNG 进行视觉审美与排版自检

# 4. 运行全局架构与语法门禁
python .agents/skills/framework-aware/scripts/check_compliance.py
```
