@abstract
class_name BaseInputSystem
extends Node

## 输入设备与键位映射系统门面契约（Input & Keybinding System Facade Contract）。[br]
##
## 本抽象基类作为业务层与 UI 层读取玩家输入、管理键鼠/手柄双轨映射及交互式改键的唯一规范入口，核心特性：[br]
## - [b]键鼠与手柄双轨双槽隔离[/b]：每个 Action 独立维护键鼠（主/副）与手柄（主/副）共 4 个 [InputChord] 槽位，改键盘绝不洗掉手柄绑定；[br]
## - [b]统一复合键（InputChord）与高阶优先消费[/b]：无缝支持键盘组合键（如 [code]Shift + Q[/code]）与手柄组合键（如 [code]LB + Y[/code]），同帧触发组合键时自动消费主键，杜绝误触单键技能；[br]
## - [b]连续移动豁免修饰锁[/b]：[method get_vector] 自动无视修饰键状态，边按 Shift 冲刺边按 WASD 走位绝不断触；[br]
## - [b]输入上下文栈（Context Stack）与防穿透门控[/b]：支持压入 [constant InputContextType.Context.UI] 挂起战斗输入，恢复时自动启用 Wait-For-Release 防止关弹窗首帧误放技能；[br]
## - [b]二段式免勾选交互录制[/b]：[method rebind_interactive_async] 自动识别“按住修饰键+主键成组合”与“单按松开成单键”；[br]
## - [b]基线快照与增量持久化[/b]：仅导出与出厂默认配置不同的增量补丁，版本升级新增 Action 永不坏档。[br]
##
## 业务代码应统一通过 [code]App.input[/code] 访问本契约提供的方法。

#region Signals
## 当玩家当前活跃的输入设备大类（键鼠/手柄）或手柄品牌（Xbox/PS/Switch/SteamDeck）发生切换时触发。
@warning_ignore("unused_signal")
signal device_changed(device_type: int, joy_brand: int)

## 当某个动作的键位映射发生修改或重置时触发（[param action] 为空表示批量重置）。
@warning_ignore("unused_signal")
signal bindings_changed(action: StringName)

## 当交互式按键录制正式开始时触发。
@warning_ignore("unused_signal")
signal rebind_started(action: StringName, device_type: int, slot: int)

## 当交互式录制中玩家按住候选修饰键（如 Shift 或手柄 LB）等待主键时触发，供 UI 实时显示 "Shift + ..."。
@warning_ignore("unused_signal")
signal rebind_preview(preview_glyph: InputGlyphInfo)

## 当交互式按键录制完成、取消或超时结束时触发。
@warning_ignore("unused_signal")
signal rebind_completed(action: StringName, result: Result)
#endregion


## 当前激活的输入设备大类（见 [enum InputDeviceType.Type]）。
var current_device: int = InputDeviceType.Type.KEYBOARD_MOUSE

## 当前连接或最后活跃的手柄硬件品牌（见 [enum InputDeviceType.JoyBrand]）。
var current_joy_brand: int = InputDeviceType.JoyBrand.XBOX

## 当前最后发生交互的手柄设备索引 ID（供手柄马达震动精准路由）。
var active_joy_id: int = 0

## 局内战斗输入总开关（设为 false 时自动清空残留按压态并屏蔽 GAMEPLAY 动作）。
var gameplay_input_enabled: bool = true


#region Gameplay & Action Polling APIs
## 获取四向合成的归一化移动向量（如 WASD / 方向键 / 左摇杆）。[br]
## 内部自动豁免修饰键（按住 Shift/Ctrl 不中断移动）并应用自定义摇杆死区。[br]
##
## [param negative_x] 左向动作名（如 [code]&"move_left"[/code]）。[br]
## [param positive_x] 右向动作名（如 [code]&"move_right"[/code]）。[br]
## [param negative_y] 上向动作名（如 [code]&"move_up"[/code]）。[br]
## [param positive_y] 下向动作名（如 [code]&"move_down"[/code]）。[br]
## [param deadzone] 自定义死区（传负数则使用全局 [method get_joy_deadzone]）。
@abstract
func get_vector(
	negative_x: StringName,
	positive_x: StringName,
	negative_y: StringName,
	positive_y: StringName,
	deadzone: float = -1.0
) -> Vector2


## 查询指定动作当前是否处于按住状态（经过组合键消费裁决与上下文门控）。
@abstract
func is_action_pressed(action: StringName) -> bool


## 查询指定动作是否在当前帧（自适应渲染帧 `_process` 与物理帧 `_physics_process`）刚刚按下。
@abstract
func is_action_just_pressed(action: StringName) -> bool


## 查询指定动作是否在当前帧（自适应渲染帧 `_process` 与物理帧 `_physics_process`）刚刚松开。
@abstract
func is_action_just_released(action: StringName) -> bool


## 获取指定动作在当前帧的连续输入强度（0.0 ~ 1.0）。
@abstract
func get_action_strength(action: StringName) -> float
#endregion


#region Input Context & State Management
## 设置局内战斗输入总开关。从 false 切回 true 时自动启用 Wait-For-Release 防关弹窗首帧穿透。
@abstract
func set_gameplay_input_enabled(enabled: bool) -> void


## 压入输入上下文作用域（如打开模态弹窗时压入 [constant InputContextType.Context.UI]）。
@abstract
func push_context(context: int) -> void


## 弹出输入上下文作用域（栈底始终保留 [constant InputContextType.Context.GAMEPLAY]）。
@abstract
func pop_context(context: int) -> void


## 获取当前处于栈顶的生效上下文（见 [enum InputContextType.Context]）。
@abstract
func get_active_context() -> int


## 强制释放全部受管动作的按压状态并清空残留缓存（用于切场景、窗口失焦或过场切入）。
@abstract
func flush_all_states() -> void


## 注册或更新业务自定义 Action 的元数据规则。[br]
## [param action] 动作名称。[br]
## [param context] 所属上下文（见 [enum InputContextType.Context]）。[br]
## [param rebindable] 是否允许玩家在设置中改键。[br]
## [param is_axis] 是否为移动/连续轴向动作（为 true 时豁免组合键修饰锁）。
@abstract
func register_action(
	action: StringName,
	context: int = InputContextType.Context.GAMEPLAY,
	rebindable: bool = true,
	is_axis: bool = false
) -> void
#endregion


#region Keybinding & Interactive Capture APIs
## 启动异步交互式按键录制（等待玩家按下单键或“修饰键+主键”组合键，并自动完成绑定与冲突裁决）。[br]
##
## [param action] 目标动作名。[br]
## [param device_type] 目标设备轨道（[enum InputDeviceType.Type]）。[br]
## [param slot] 目标槽位（[enum InputBindingSlot.Slot]）。[br]
## [param conflict_policy] 冲突裁决策略（默认 [constant InputConflictPolicy.Policy.SWAP] 无感互换）。[br]
## [param timeout_sec] 超时秒数（默认 5.0 秒，按 ESC 或手柄 Back 键可随时取消）。[br]
## @return 成功时返回 [code]Result.ok(InputGlyphInfo)[/code]；取消或冲突时返回携带 [InputError] 的失败 [Result]。
@abstract
func rebind_interactive_async(
	action: StringName,
	device_type: int,
	slot: int = InputBindingSlot.Slot.PRIMARY,
	conflict_policy: int = InputConflictPolicy.Policy.SWAP,
	timeout_sec: float = 5.0
) -> Result


## 取消当前正在进行的交互式按键录制。
@abstract
func cancel_rebind() -> void


## 查询当前是否正处于交互式按键录制等待状态。
@abstract
func is_rebinding() -> bool


## 通过代码直接将一个 [InputChord]（单键或组合键）绑定至指定动作槽位。[br]
## @return 成功时返回 [code]Result.ok(affected_actions: Array[StringName])[/code]。
@abstract
func bind_chord(
	action: StringName,
	chord: InputChord,
	slot: int = InputBindingSlot.Slot.PRIMARY,
	conflict_policy: int = InputConflictPolicy.Policy.SWAP
) -> Result


## 通过代码直接将单个 [InputEvent] 绑定至指定动作槽位。
@abstract
func bind_event(
	action: StringName,
	event: InputEvent,
	slot: int = InputBindingSlot.Slot.PRIMARY,
	conflict_policy: int = InputConflictPolicy.Policy.SWAP
) -> Result


## 清空指定动作在特定设备与槽位下的按键绑定。
@abstract
func unbind_slot(action: StringName, device_type: int, slot: int = InputBindingSlot.Slot.PRIMARY) -> Result


## 恢复出厂默认键位映射。[br]
## [param action] 为空时重置全部动作；非空时仅重置该动作。[br]
## [param device_type] 为 -1 时同时重置键鼠与手柄；否则仅重置指定设备轨道。
@abstract
func reset_to_default(action: StringName = &"", device_type: int = -1) -> Result
#endregion


#region Glyph Prompts, Deadzone & Persistence APIs
## 获取指定动作在当前活跃设备（或指定设备）下的展示信息（可读按键文本、组合键拆解标签、图标 Key）。[br]
## [param action] 动作名称。[br]
## [param device_type] 传 -1 时自动取当前活跃设备 [member current_device]。[br]
## [param slot] 槽位枚举（默认取主槽位，若主槽位为空且为自动查询则回退副槽位）。
@abstract
func get_action_glyph(
	action: StringName,
	device_type: int = -1,
	slot: int = InputBindingSlot.Slot.PRIMARY
) -> InputGlyphInfo


## 获取指定动作在特定设备与槽位下的原始 [InputChord] 副本。
@abstract
func get_action_chord(
	action: StringName,
	device_type: int,
	slot: int = InputBindingSlot.Slot.PRIMARY
) -> InputChord


## 获取全部受管动作名称列表（可按 [param context_filter] 过滤）。
@abstract
func get_managed_actions(context_filter: int = -1) -> Array[StringName]


## 设置全局手柄摇杆死区（0.05 ~ 0.90）。
@abstract
func set_joy_deadzone(deadzone: float) -> void


## 获取全局手柄摇杆死区。
@abstract
func get_joy_deadzone() -> float


## 手动切换或模拟当前输入设备与手柄品牌（用于 UI 预览或无物理手柄环境下的调试测试）。
@abstract
func simulate_device(device_type: int, joy_brand: int = -1) -> void


## 导出用户自定义键位增量补丁字典（仅包含与出厂默认不同的槽位，直接存入 GameSettingsModel）。
@abstract
func export_bindings() -> Dictionary


## 从存档增量字典恢复用户自定义键位映射（由启动管线 ApplySettingsStep 调用）。
@abstract
func import_bindings(payload: Dictionary) -> Result
#endregion
