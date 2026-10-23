# Framework · Cursor (自定义鼠标指针、五层交互裁决与顶层粒子系统)

> 统一接管全游戏鼠标指针视觉主题（`CursorThemeConfig`）、五层优先级交互状态自动嗅探与裁决（`CursorStateResolver`）、OS 硬件光标与顶层画布动态光标双模互斥渲染（`CursorPointerDriver`）以及移动星尘拖尾与点击爆裂粒子对象池（`CursorVfxStage`）。对外唯一门面入口为 `App.cursor`（[`BaseCursorSystem`](base_cursor_system.gd)）。

```text
src/framework/modules/cursor/
├── _doc_cursor.md                     # 本文档（三大微内核架构、五层裁决漏斗与使用范式）
├── base_cursor_system.gd              # 公开门面契约 BaseCursorSystem (App.cursor，详尽注释)
│
├── types/                             # [公开枚举与类型定义]
│   └── cursor_shape_type.gd           # 11 种语义光标类型枚举与按压配对映射 (CursorShapeType)
│
├── model/                             # [公开配置资源模型 (*Config / *Entry)]
│   ├── cursor_style_entry.gd          # 单一形状的样式配置资源：normal/pressed 贴图、hotspot、动态预制体 .tscn (CursorStyleEntry)
│   └── cursor_theme_config.gd         # 鼠标主题总配置资源：形状列表、DPI 缩放、拖尾/点击粒子参数与内置程序化工厂 (CursorThemeConfig)
│
└── impl/                              # [私有实现收敛] 三大单一职责微内核 + 顶层协调器
	├── cursor_system.gd               # 门面协调器 (CursorSystem extends BaseCursorSystem，串联三大微内核、手柄显隐与窗口锁边)
	├── cursor_state_resolver.gd       # 微内核 ①：五层优先级纯逻辑状态裁决器 (零渲染耦合)
	├── cursor_pointer_driver.gd       # 微内核 ②：硬件/软件双模指针驱动 (DPI 自适应重采样 + 软件动态节点互斥 + 脉冲补间)
	└── cursor_vfx_stage.gd            # 微内核 ③：顶层粒子与特效舞台 (移动星尘拖尾 + 8 槽位点击爆裂环形对象池)
```

---

## 一、 核心工程设计机制

1. **三大单一职责微内核正交解耦**：
   - **微内核 ① [`CursorStateResolver`](impl/cursor_state_resolver.gd)（纯逻辑 · 只算状态）**：按五层优先级漏斗实时求值当前胜出的 `(shape, is_pressed, layer)`，不触碰任何贴图或引擎渲染 API；
   - **微内核 ② [`CursorPointerDriver`](impl/cursor_pointer_driver.gd)（纯指针 · 只管本体）**：根据样式配置在 **OS 硬件光标**（0 帧延迟 + 高分屏 DPI 自动重采样）与 **顶层画布软件动态光标**（支持旋转、`.tscn` 预制体与 [`pulse()`](base_cursor_system.gd) 射击扩散回弹）间无缝互斥切换，杜绝双鼠标重叠；
   - **微内核 ③ [`CursorVfxStage`](impl/cursor_vfx_stage.gd)（纯特效 · 只管粒子）**：挂载于最高画布层 `BaseDisplaySystem.Layer.CURSOR (120)`，独立驱动随鼠标移动发射的星尘丝带拖尾（静止 `65ms` 自动停喷）与 8 槽位环形复用的点击爆裂特效池（零运行时 `instantiate/queue_free` 开销）。
2. **五层优先级交互状态裁决漏斗（Zero-Conflict Interaction Funnel）**：
   - **Layer 5 · 强锁覆盖栈（`push_override` / `pop_override`）**：如背包拖拽中锁定 `GRABBED`、指向性技能选点、网络等待锁定 `WAIT`，屏蔽沿途路过的一切按钮或世界物体干扰；
   - **Layer 4 · UI 控件自动嗅探与声明式绑定（`gui_get_hovered_control` + `bind_control`）**：
	 - 业务零代码自动识别：悬停于可用 `BaseButton` 自动切换为 `POINTER`；悬停于 `disabled == true` 按钮自动切换为 `FORBIDDEN`；悬停于 `LineEdit` / `TextEdit` 自动切换为 `IBEAM`；
	 - 支持 `App.cursor.bind_control(ctrl, CursorShapeType.Shape.GRAB)` 为特定 UI 区域绑定专属光标；
   - **Layer 3 · 局内世界物体悬停（`bind_hover_node` / `set_world_hover`）**：
	 - 仅在鼠标未被上层 UI 控件遮挡且处于 `GAMEPLAY` 上下文时生效（如悬停于 NPC/宝箱变 `INTERACT`，悬停于敌人变 `ATTACK`，悬停于线索变 `INSPECT`）；
	 - `bind_hover_node(node, shape)` 自动监听 `tree_exiting`，怪物死亡或物体销毁时自动清除悬停栈，杜绝幽灵状态；
   - **Layer 2 · 输入上下文基准（`InputContext`）**：当处于 `GAMEPLAY` 时使用场景设定的战斗光标（如 `CROSSHAIR`）；当打开弹窗切入 `UI` 上下文时自动回退为 `DEFAULT`；
   - **Layer 1 · 全局兜底（`DEFAULT`）**。
3. **键鼠 ↔ 手柄显隐与双屏防滑出锁边联动**：
   - 监听 [`Bus.input_device_changed`](../../core/autoload/event_bus.gd)：切入手柄（`JOYPAD`）时自动隐藏鼠标指针与粒子舞台，晃动鼠标切回 `KEYBOARD_MOUSE` 时瞬间恢复；
   - 开启 `App.cursor.set_confined(true)` 后，在 `GAMEPLAY` 期间自动启用 `MOUSE_MODE_CONFINED` 防止鼠标滑出副屏失焦，而在打开弹窗（`UI` 上下文）或切后台（`Bus.app_paused`）时自动临时解除锁边。

---

## 二、 使用范式

> **默认行为说明**：框架启动时默认不挂载任何自定义鼠标主题（保持操作系统原生鼠标，且不触发拖尾与点击粒子）。业务层需显式调用 `App.cursor.set_theme(theme)` 激活自定义鼠标；传入 `null` 可随时恢复系统原生鼠标。完整 MSVP 交互教学案例参见 [`src/test/cursor/_doc_cursor.md`](../../../test/cursor/_doc_cursor.md)。

```gdscript
# 0. 挂载自定义鼠标主题（传 null 可随时卸载并恢复系统原生鼠标）
App.cursor.set_theme(CursorThemeConfig.create_procedural_default())

# 1. 进入战斗场景：设置局内基准光标为战术准星，并开启双屏防滑出锁边
func _on_enter(_params: BaseParams = null) -> void:
	App.cursor.set_gameplay_cursor(CursorShapeType.Shape.CROSSHAIR)
	App.cursor.set_confined(true)

# 2. 绑定局内宝箱/NPC 与敌人的悬停光标（节点销毁时自动解绑）
App.cursor.bind_hover_node(chest_area_2d, CursorShapeType.Shape.INTERACT)
App.cursor.bind_hover_node(boss_weakpoint_area, CursorShapeType.Shape.ATTACK, 10)

# 3. 绑定特殊可拖拽 UI 背包格（悬停显示张开手 GRAB，按住左键自动变握紧手 GRABBED）
App.cursor.bind_control(item_slot_panel, CursorShapeType.Shape.GRAB)

# 4. 拖拽物品跨格子移动期间：压入强锁覆盖，松手时弹出
App.cursor.push_override(&"inventory_drag", CursorShapeType.Shape.GRABBED)
# ... 拖拽结束 ...
App.cursor.pop_override(&"inventory_drag")

# 5. 开火或释放重型技能时：触发准星扩散回弹脉冲
App.cursor.pulse(1.42, 0.12)
```
