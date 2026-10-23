# Cursor Test & Custom Mouse Tutorial (自定义鼠标架构教学与契约验证模块)

> 本模块用于教学演示如何基于 `App.cursor`（[`BaseCursorSystem`](../../framework/modules/cursor/base_cursor_system.gd) / [`CursorSystem`](../../framework/modules/cursor/impl/cursor_system.gd)）搭建、配置、切换及卸载自定义鼠标，严格遵循 [`_doc_test.md`](../_doc_test.md) 的 **MSVP 交互模块模式** 与 [`_doc_game.md`](../../game/_doc_game.md) 的 **`view/scene/<domain>/`** 单元目录规范。

---

## 一、 架构目录树

```text
src/test/cursor/
├── _doc_cursor.md                                       # 本模块架构说明与自定义鼠标搭建教程
├── model/
│   └── cursor_test_state.gd                             # 响应式鼠标演练场运行时状态模型 (extends RefCounted)
├── service/
│   └── cursor_test_service.gd                           # 主题构建、五层交互绑定与 6 项契约自检服务 (extends RefCounted)
├── presenter/
│   └── cursor_playground_presenter.gd                   # 演练场协调器 (extends RefCounted)
└── view/
	└── scene/
		└── playground/
			├── cursor_playground_scene.tscn             # 声明式演练场主场景
			├── cursor_playground_scene.gd               # 演练场场景生命周期 (extends BaseScene)
			└── cursor_playground_view.gd                # 演练场被动视图 (extends BaseView)
```

---

## 二、 如何在业务中搭建自定义鼠标（3 步上手教程）

框架 `App.cursor` 在游戏启动时**默认保持操作系统原生光标**（不强行挂载自定义鼠标，也不生成拖尾与点击粒子）。当项目或特定关卡需要启用自定义鼠标时，仅需以下 3 步：

### 第 1 步：准备并挂载鼠标主题 (`CursorThemeConfig`)

有两种方式构建 [`CursorThemeConfig`](../../framework/modules/cursor/model/cursor_theme_config.gd)：

1. **编辑器 `.tres` 资源配置（推荐美术/策划工作流）**：
   - 在 Godot 文件系统中右键 `新建资源 (New Resource)` -> 选择 `CursorThemeConfig` 保存为 `.tres`；
   - 在 Inspector 中填入各语义形状的 [`CursorStyleEntry`](../../framework/modules/cursor/model/cursor_style_entry.gd)（设置常态贴图 `normal_texture`、按压态贴图 `pressed_texture` 与热点坐标 `hotspot`）；
   - 在业务初始化服务中调用：
     ```gdscript
     var theme: CursorThemeConfig = preload("res://src/assets/resources/global/res_global_cursor_theme.tres")
     App.cursor.set_theme(theme)
     ```
2. **代码组装自定义主题（详见 [`CursorTestService.build_crimson_tactical_theme()`](service/cursor_test_service.gd#L81-L116)）**：
   - 以 `CursorThemeConfig.create_procedural_default()` 或 `CursorThemeConfig.new()` 起步，按需替换指定语义形状的贴图、热点与拖尾/点击粒子配色；
   - 若需随时卸载自定义鼠标、恢复操作系统原生默认鼠标，直接调用：
     ```gdscript
     App.cursor.set_theme(null)
     ```

### 第 2 步：利用五层优先级漏斗（L1 ~ L5）声明式绑定光标

无需在业务 `Control` 或 `Area2D` 脚本中编写繁琐的 `_on_mouse_entered` / `_on_mouse_exited` 恢复逻辑，`App.cursor` 按以下五层漏斗每帧自动裁决：

| 优先级 | 层级名称 | 适用场景与一行绑定方式 |
| :--- | :--- | :--- |
| **L5（最高）** | 全局强锁覆盖栈 (`Override Stack`) | 网络请求转圈、技能选点瞄准、过场动画锁定：<br>`App.cursor.push_override(&"net_saving", CursorShapeType.Shape.WAIT)`<br>结束时调用 `App.cursor.pop_override(&"net_saving")` |
| **L4** | UI 控件悬停层 (`UI Hover`) | - 普通 `Button` / `LineEdit` / 禁用按钮：只要设置原生 `mouse_default_cursor_shape`，框架自动映射为 `POINTER` / `TEXT_EDIT` / `DISABLED`；<br>- 特殊控件（如可拖拽卡牌、词条提示）：调用 `App.cursor.bind_control(card_node, CursorShapeType.Shape.GRAB)`，按住左键自动变为 `GRABBED` |
| **L3** | 世界实体悬停层 (`World Hover`) | 2D/3D 宝箱、NPC、敌方靶标：<br>`App.cursor.bind_hover_node(enemy_area, CursorShapeType.Shape.ATTACK, 10)`<br>实体销毁退树时自动解绑，且被上层 UI 遮挡时自动失效 |
| **L2** | 输入上下文基准层 (`Gameplay Context`) | 局内射击/割草态切换默认准星：<br>`App.cursor.set_gameplay_cursor(CursorShapeType.Shape.CROSSHAIR)` |
| **L1（保底）** | 全局默认层 (`Default`) | 保底回退为 `CursorShapeType.Shape.DEFAULT` |

### 第 3 步：按需触发射击脉冲与特效控制

- **射击/释放技能准星弹性脉冲**：调用 `App.cursor.pulse(1.45, 0.15)`（需处于软件画布光标模式 `App.cursor.set_software_cursor_preferred(true)`）。
- **独立开关粒子舞台**：调用 `App.cursor.set_vfx_enabled(enable_trail, enable_click)`。
- **双显示器战斗期窗口锁边**：调用 `App.cursor.set_confined(true)`。

---

## 三、 内置自动化契约验证用例（6 项）

| 用例编号 | 验证项 | 预期结果 |
| :--- | :--- | :--- |
| **CASE 1** | 主题结构与 11 种语义形态完整性 | `App.cursor.get_theme()` 包含全部 11 种 `CursorShapeType.Shape` 条目及常态/按压态贴图 |
| **CASE 2** | 五层优先级漏斗与左键按压变态 (`GRAB -> GRABBED`) | `L5 Override > L4 UI Control > L3 World Hover > L2 InputContext > L1 Default` 严格按优先级裁决 |
| **CASE 3** | 世界实体悬停退树自动清理 (`bind_hover_node`) | 绑定悬停的节点 `free()` 退树后自动清理悬停句柄，零幽灵残留 |
| **CASE 4** | 软件光标与射击后坐力脉冲 (`pulse`) | 软指针模式与 `App.cursor.pulse(1.45, 0.15)` 弹性扩缩正常执行 |
| **CASE 5** | 粒子伴生舞台（拖尾 + 8 槽位点击波对象池循环复用） | 连续高频触发 10 次点击波（超过 8 槽位上限）安全环形复用，零报错 |
| **CASE 6** | 手柄设备联动自动隐藏与窗口边界锁边 (`set_confined`) | 切换 `JOYPAD` 自动隐藏鼠标与拖尾，切回 `KEYBOARD_MOUSE` 立即恢复 |

---

## 四、 运行方式

1. **编辑器内交互运行**：在 Godot 编辑器中打开 [`cursor_playground_scene.tscn`](view/scene/playground/cursor_playground_scene.tscn) 并按 `F6` 即可直接体验主题切换、五层悬停变态、星尘拖尾与点击波粒子。
2. **命令行无头验证**：
   ```bash
   Godot --headless --path . res://src/test/cursor/view/scene/playground/cursor_playground_scene.tscn --quit-after 60
   ```
