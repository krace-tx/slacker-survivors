@abstract
class_name BaseCursorSystem
extends Node

## 全局自定义鼠标指针、五层交互状态裁决与顶层粒子特效门面契约（Cursor System Facade Contract）。[br]
##
## [b]核心职责（三大微内核正交架构）：[/b][br]
## 1. [b]五层优先级交互状态裁决[/b]：自动按「强锁覆盖栈 (`Override`) > UI 控件自动嗅探 (`gui_get_hovered_control`) > 局内世界物体悬停 (`WorldHover`) > 输入上下文 (`GAMEPLAY/UI`) > 全局默认 (`DEFAULT`)」实时裁决当前形状与按压态；[br]
## 2. [b]硬件/软件双模指针驱动[/b]：支持 OS 硬件光标（0 帧延迟 + 高分屏 DPI 自动重采样）与顶层画布软件动态光标（`.tscn` 预制体 + 射击扩散脉冲）无缝互斥切换；[br]
## 3. [b]顶层粒子与特效伴随舞台[/b]：在专属 `Layer.CURSOR (120)` 画布层提供零帧延迟跟随的移动拖尾粒子（Trail VFX）与 8 槽位环形复用的点击爆裂特效池（Click Burst Pool）；[br]
## 4. [b]设备显隐与双屏锁边联动[/b]：切入手柄（`JOYPAD`）时自动隐藏鼠标与粒子，战斗期支持开启 `MOUSE_MODE_CONFINED` 双屏防滑出锁边并在打开弹窗/切后台时自动临时解锁。[br]
##
## 业务代码统一通过 [code]App.cursor[/code] 访问本契约提供的方法。

#region Signals
## 当最终裁决生效的光标形状或按压状态发生变更时发射。
@warning_ignore("unused_signal")
signal cursor_shape_changed(new_shape: int, is_pressed: bool)

## 当光标可见性发生变更（如键鼠与手柄切换）时发射。
@warning_ignore("unused_signal")
signal cursor_visibility_changed(visible: bool)
#endregion


#region 1. Theme & Visual Mode Configuration
## 应用自定义鼠标主题配置资源（传入 null 时恢复为内置程序化默认主题）。[br]
## [param theme] 鼠标主题资源（见 [CursorThemeConfig]）。
@abstract
func set_theme(theme: CursorThemeConfig) -> void


## 获取当前生效的鼠标主题配置资源。
@abstract
func get_theme() -> CursorThemeConfig


## 设置局内战斗上下文（`InputContextType.Context.GAMEPLAY`）下的基准光标形状（如 [constant CursorShapeType.Shape.CROSSHAIR]）。[br]
## 当打开弹窗切入 `UI` 上下文时会自动临时切回 `DEFAULT`，关闭弹窗后自动恢复为该战斗光标。
@abstract
func set_gameplay_cursor(shape: int) -> void


## 获取当前配置的局内战斗基准光标形状。
@abstract
func get_gameplay_cursor() -> int


## 设置是否全局偏好使用画布软件光标模式（开启后所有状态均支持平滑缩放与脉冲动画）。
@abstract
func set_software_cursor_preferred(preferred: bool) -> void


## 当前是否正在使用画布软件光标模式渲染指针本体。
@abstract
func is_using_software_cursor() -> bool
#endregion


#region 2. Five-Layer Interaction Cursor Switching
## 压入最高优先级的强锁光标覆盖（适用于背包拖拽中 `GRABBED`、指向性技能选点、网络等待 `WAIT`）。[br]
## 在调用 [method pop_override] 弹出前，屏蔽沿途一切按钮或世界物体的悬停光标干扰。[br]
## [param token] 唯一标识令牌（如 `&"inventory_drag"`）。[br]
## [param shape] 目标语义光标形状（见 [enum CursorShapeType.Shape]）。[br]
## [param priority] 覆盖优先级（数值越大越优先，默认 `100`）。
@abstract
func push_override(token: StringName, shape: int, priority: int = 100) -> void


## 弹出指定令牌的强锁光标覆盖，立即恢复底层应有的光标状态。
@abstract
func pop_override(token: StringName) -> void


## 清空全部强锁光标覆盖栈。
@abstract
func clear_overrides() -> void


## 为指定 UI 控件声明式绑定专属悬停与按压光标形状（如可拖拽格子绑定 `GRAB` -> `GRABBED`）。[br]
## [param control] 目标 UI 控件节点。[br]
## [param hover_shape] 鼠标悬停时的光标形状。[br]
## [param pressed_shape] 鼠标在该控件上按住左键时的光标形状（传 `-1` 表示自动使用配对按压态）。
@abstract
func bind_control(control: Control, hover_shape: int, pressed_shape: int = -1) -> void


## 解除指定 UI 控件的自定义光标绑定。
@abstract
func unbind_control(control: Control) -> void


## 为局内世界交互物体（如 [Area2D] / [CollisionObject2D] / [CollisionObject3D] / [Control]）绑定悬停光标。[br]
## 内部自动连接 `mouse_entered`、`mouse_exited` 与 `tree_exiting` 信号，物体销毁（`queue_free`）时自动清理，绝不残留幽灵状态。[br]
## [param node] 具备 `mouse_entered` / `mouse_exited` 信号的场景节点。[br]
## [param hover_shape] 悬停时切换的语义光标形状（如宝箱/NPC 用 `INTERACT`，敌人用 `ATTACK`）。[br]
## [param priority] 多个世界物体重叠时的裁决优先级（默认 `0`）。
@abstract
func bind_hover_node(node: Node, hover_shape: int, priority: int = 0) -> void


## 手动设置某个局内世界交互源的悬停光标状态（仅在未被上层 UI 控件遮挡且处于 `GAMEPLAY` 上下文时生效）。
@abstract
func set_world_hover(source_id: Variant, shape: int, priority: int = 0) -> void


## 手动清除某个局内世界交互源的悬停光标状态。
@abstract
func clear_world_hover(source_id: Variant) -> void
#endregion


#region 3. Particle VFX & Dynamic Impulse
## 开启或关闭鼠标移动拖尾粒子与点击爆裂特效。
@abstract
func set_vfx_enabled(trail_enabled: bool, click_enabled: bool = true) -> void


## 查询当前是否已开启鼠标移动拖尾特效。
@abstract
func is_trail_vfx_enabled() -> bool


## 查询当前是否已开启鼠标点击爆裂特效。
@abstract
func is_click_vfx_enabled() -> bool


## 触发一次光标扩散回弹脉冲（适用于射击后坐力、释放技能、重击反馈）。[br]
## [param scale_kick] 瞬时放大倍率（如 `1.38`）。[br]
## [param duration] 回弹总时长（秒，默认 `0.12`）。
@abstract
func pulse(scale_kick: float = 1.35, duration: float = 0.12) -> void


## 在指定画布坐标（默认当前鼠标位置）手动触发一次点击爆裂粒子与水波纹特效。
@abstract
func spawn_click_burst(canvas_pos: Vector2 = Vector2(-1.0, -1.0)) -> void
#endregion


#region 4. Confinement, Visibility & Diagnostics
## 设置是否在局内战斗（`GAMEPLAY`）期间将鼠标限制在游戏窗口边界内（防止双显示器玩家滑出副屏失焦）。[br]
## 打开 UI 弹窗或切后台时会自动临时解除锁边，回到战斗时自动恢复。
@abstract
func set_confined(confined: bool) -> void


## 查询当前是否开启了战斗期窗口边界锁边策略。
@abstract
func is_confined() -> bool


## 查询当前鼠标指针是否处于可见状态（手柄模式下自动为 `false`）。
@abstract
func is_cursor_visible() -> bool


## 获取当前裁决生效的语义光标形状枚举值（见 [enum CursorShapeType.Shape]）。
@abstract
func get_current_shape() -> int


## 获取当前鼠标是否处于左键按压形变状态。
@abstract
func is_pressed_state() -> bool


## 获取鼠标子系统的实时诊断快照。
@abstract
func get_diagnostics() -> Dictionary
#endregion
