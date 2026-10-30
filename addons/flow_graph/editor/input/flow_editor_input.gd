@tool
class_name FlowEditorInput
extends RefCounted

## FlowGraph 编辑器统一鼠键与手势语义映射服务（Unified Mouse, Keyboard & Gesture Input Mapper）。[br]
##
## [b]核心职责：[/b][br]
## 1. 将工作台、2D 流转画布、原位改名框、快速搜索弹窗与检视器条目的全部鼠标按键、滚轮、触控板手势、修饰键及键盘快捷键统一抽象为语义动作；[br]
## 2. 隔离底层物理键码（物理常量仅存在于 [`flow_input_bindings.gd`](flow_input_bindings.gd)），支持通过 `EditorSettings`（`flow_graph/editor/input_overrides`）或 API 动态重映射；[br]
## 3. 自动适配 Windows / Linux（`Ctrl`）与 macOS（`Cmd`）修饰键匹配及快捷键提示文案格式化。

const Bindings = preload(FlowGraphContracts.SCRIPT_INPUT_BINDINGS)

#region 语义动作、指针角色与修饰键常量

## 工作台全局动作作用域
const WB_SAVE: StringName = &"wb.save"
const WB_UNDO: StringName = &"wb.undo"
const WB_REDO: StringName = &"wb.redo"

## 画布动作作用域
const CANVAS_UNDO: StringName = &"canvas.undo"
const CANVAS_REDO: StringName = &"canvas.redo"
const CANVAS_SELECT_ALL: StringName = &"canvas.select_all"
const CANVAS_DUPLICATE: StringName = &"canvas.duplicate"
const CANVAS_DELETE: StringName = &"canvas.delete"
const CANVAS_RENAME: StringName = &"canvas.rename"
const CANVAS_APPEND_DOWNSTREAM: StringName = &"canvas.append_downstream"
const CANVAS_QUICK_ADD: StringName = &"canvas.quick_add"
const CANVAS_SPACE_HAND_OR_PICKER: StringName = &"canvas.space_hand_or_picker"
const CANVAS_FIT_OR_FRAME: StringName = &"canvas.fit_or_frame"
const CANVAS_TOGGLE_BREAKPOINT: StringName = &"canvas.toggle_breakpoint"
const CANVAS_CANCEL_OR_CLEAR: StringName = &"canvas.cancel_or_clear"

## 弹窗与原位输入模态作用域
const MODAL_CONFIRM: StringName = &"modal.confirm"
const MODAL_CANCEL: StringName = &"modal.cancel"
const MODAL_NAV_NEXT: StringName = &"modal.nav_next"
const MODAL_NAV_PREV: StringName = &"modal.nav_prev"

## 鼠标指针语义角色
const PTR_PRIMARY: StringName = &"ptr.primary"
const PTR_PAN_DEDICATED: StringName = &"ptr.pan_dedicated"
const PTR_CONTEXT_OR_PAN: StringName = &"ptr.context_or_pan"
const PTR_WHEEL_ZOOM_IN: StringName = &"ptr.wheel_zoom_in"
const PTR_WHEEL_ZOOM_OUT: StringName = &"ptr.wheel_zoom_out"

## 交互修饰键语义角色
const MOD_TOGGLE_SELECT: StringName = &"mod.toggle_select"
const MOD_ADDITIVE_SELECT: StringName = &"mod.additive_select"
const MOD_BYPASS_SNAP: StringName = &"mod.bypass_snap"

#endregion


static var _initialized: bool = false
static var _key_bindings: Dictionary = {}
static var _pointer_buttons: Dictionary = {}


#region 初始化与自定义重映射接口

static func _ensure_init() -> void:
	if _initialized:
		return
	_initialized = true
	reset_to_defaults(false)
	reload_from_editor_settings()


## 重置全部鼠键映射为内置默认表。
static func reset_to_defaults(persist_clear: bool = false) -> void:
	_initialized = true
	_key_bindings = Bindings.build_default_key_bindings()
	_pointer_buttons = Bindings.POINTER_BUTTONS.duplicate()
	if persist_clear and Engine.is_editor_hint():
		var es: EditorSettings = EditorInterface.get_editor_settings()
		if es != null and es.has_setting(FlowGraphContracts.SETTING_INPUT_OVERRIDES):
			es.set_setting(FlowGraphContracts.SETTING_INPUT_OVERRIDES, {})


## 从 `EditorSettings` 加载用户自定义键位覆盖表（若存在）。
static func reload_from_editor_settings() -> void:
	_ensure_init()
	if not Engine.is_editor_hint():
		return
	var es: EditorSettings = EditorInterface.get_editor_settings()
	if es == null or not es.has_setting(FlowGraphContracts.SETTING_INPUT_OVERRIDES):
		return
	var raw: Variant = es.get_setting(FlowGraphContracts.SETTING_INPUT_OVERRIDES)
	if not (raw is Dictionary):
		return
	var overrides: Dictionary = raw as Dictionary
	for k: Variant in overrides.keys():
		var action_id: StringName = StringName(str(k))
		var val: Variant = overrides[k]
		if val is Array:
			var parsed_list: Array[Dictionary] = []
			for item_v: Variant in val as Array:
				if item_v is Dictionary:
					var d: Dictionary = item_v as Dictionary
					parsed_list.append({
						"key": int(d.get("key", 0)),
						"cmd_or_ctrl": bool(d.get("cmd_or_ctrl", false)),
						"shift": bool(d.get("shift", false)),
						"alt": bool(d.get("alt", false)),
					})
			if not parsed_list.is_empty():
				_key_bindings[action_id] = parsed_list
		elif val is int and _pointer_buttons.has(action_id):
			_pointer_buttons[action_id] = int(val)


## 运行期或测试期覆盖指定语义动作的键盘组合绑定。
static func set_action_bindings(action: StringName, chords: Array[Dictionary]) -> void:
	_ensure_init()
	_key_bindings[action] = chords.duplicate(true)


## 运行期或测试期覆盖指定指针语义角色的鼠标按键。
static func set_pointer_button(pointer_role: StringName, button_index: MouseButton) -> void:
	_ensure_init()
	_pointer_buttons[pointer_role] = button_index

#endregion


#region 键盘动作解析与物理状态查询

## 按工作台全局作用域匹配首个命中的动作（未命中返回 `&""`）。
static func resolve_workbench_action(event: InputEvent, allow_echo: bool = false) -> StringName:
	return _resolve_in_order(event, Bindings.WORKBENCH_ORDER, allow_echo)


## 按画布作用域匹配首个命中的按下动作（未命中返回 `&""`）。
static func resolve_canvas_key_action(event: InputEvent, allow_echo: bool = false) -> StringName:
	return _resolve_in_order(event, Bindings.CANVAS_ORDER, allow_echo)


## 按模态输入框/快速搜索面板作用域匹配首个命中的动作（未命中返回 `&""`）。
static func resolve_modal_action(event: InputEvent, allow_echo: bool = true) -> StringName:
	return _resolve_in_order(event, Bindings.MODAL_ORDER, allow_echo)


## 判断 `event` 是否为指定语义动作的键盘按下事件。
static func is_key_press(event: InputEvent, action: StringName, allow_echo: bool = false) -> bool:
	_ensure_init()
	if not (event is InputEventKey):
		return false
	var ke: InputEventKey = event as InputEventKey
	if not ke.pressed or (ke.echo and not allow_echo):
		return false
	return _matches_key_chords(ke, action, true)


## 判断 `event` 是否为指定语义动作的主键松开事件（忽略松开时的修饰键先后顺序）。
static func is_key_release(event: InputEvent, action: StringName) -> bool:
	_ensure_init()
	if not (event is InputEventKey):
		return false
	var ke: InputEventKey = event as InputEventKey
	if ke.pressed or ke.echo:
		return false
	return _matches_key_chords(ke, action, false)


## 查询指定动作的物理按键当前是否仍处于系统按住态（用于防失焦卡键自愈）。
static func is_physical_key_held(action: StringName) -> bool:
	_ensure_init()
	if not _key_bindings.has(action):
		return false
	var chords: Array = _key_bindings[action] as Array
	for chord_v: Variant in chords:
		var chord: Dictionary = chord_v as Dictionary
		var k_code: Key = int(chord.get("key", 0)) as Key
		if k_code != 0 and Input.is_key_pressed(k_code):
			return true
	return false


static func _resolve_in_order(event: InputEvent, order: Array[StringName], allow_echo: bool) -> StringName:
	_ensure_init()
	if not (event is InputEventKey):
		return &""
	var ke: InputEventKey = event as InputEventKey
	if not ke.pressed or (ke.echo and not allow_echo):
		return &""
	for act: StringName in order:
		if _matches_key_chords(ke, act, true):
			return act
	return &""


static func _matches_key_chords(ke: InputEventKey, action: StringName, check_modifiers: bool) -> bool:
	if not _key_bindings.has(action):
		return false
	var ev_code: int = int(ke.keycode) if int(ke.keycode) != 0 else int(ke.physical_keycode)
	var ev_cmd: bool = ke.is_command_or_control_pressed() or ke.ctrl_pressed
	var chords: Array = _key_bindings[action] as Array
	for chord_v: Variant in chords:
		var chord: Dictionary = chord_v as Dictionary
		if int(chord.get("key", -1)) != ev_code:
			continue
		if not check_modifiers:
			return true
		if (
			bool(chord.get("cmd_or_ctrl", false)) == ev_cmd
			and bool(chord.get("shift", false)) == ke.shift_pressed
			and bool(chord.get("alt", false)) == ke.alt_pressed
		):
			return true
	return false

#endregion


#region 鼠标指针、滚轮缩放、触控板手势与修饰键判定

## 判断事件是否属于指定指针角色（不区分按下或松开）。
static func is_pointer_button(event: InputEvent, pointer_role: StringName) -> bool:
	_ensure_init()
	if not (event is InputEventMouseButton) or not _pointer_buttons.has(pointer_role):
		return false
	return int((event as InputEventMouseButton).button_index) == int(_pointer_buttons[pointer_role])


## 判断事件是否为指定指针角色的按下事件。
static func is_pointer_press(event: InputEvent, pointer_role: StringName) -> bool:
	return is_pointer_button(event, pointer_role) and (event as InputEventMouseButton).pressed


## 判断事件是否为指定指针角色的松开事件。
static func is_pointer_release(event: InputEvent, pointer_role: StringName) -> bool:
	return is_pointer_button(event, pointer_role) and not (event as InputEventMouseButton).pressed


## 判断事件是否为指定指针角色的双击按下事件。
static func is_pointer_double_click(event: InputEvent, pointer_role: StringName) -> bool:
	return is_pointer_press(event, pointer_role) and (event as InputEventMouseButton).double_click


## 判断事件是否为应当触发画布焦点抢占与收起浮层输入框的鼠标点击。
static func is_canvas_focus_click(event: InputEvent) -> bool:
	if not (event is InputEventMouseButton):
		return false
	var mb: InputEventMouseButton = event as InputEventMouseButton
	return mb.pressed and Bindings.CANVAS_FOCUS_BUTTONS.has(mb.button_index)


## 统一解析鼠标滚轮缩放或触控板捏合缩放倍率（非缩放事件返回 `0.0`）。
static func resolve_zoom_factor(event: InputEvent) -> float:
	_ensure_init()
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if not mb.pressed:
			return 0.0
		var step: float = pow(Bindings.WHEEL_ZOOM_STEP, maxf(mb.factor, 1.0) if mb.factor > 0.0 else 1.0)
		if int(mb.button_index) == int(_pointer_buttons[PTR_WHEEL_ZOOM_IN]):
			return step
		if int(mb.button_index) == int(_pointer_buttons[PTR_WHEEL_ZOOM_OUT]):
			return 1.0 / step
	elif event is InputEventMagnifyGesture:
		var mg: InputEventMagnifyGesture = event as InputEventMagnifyGesture
		if not is_equal_approx(mg.factor, 1.0) and mg.factor > 0.0:
			return clampf(mg.factor, 0.75, 1.35)
	return 0.0


## 统一解析触控板双指平移增量（非平移手势返回 `Vector2.ZERO`）。
static func resolve_pan_gesture_delta(event: InputEvent) -> Vector2:
	if event is InputEventPanGesture:
		return (event as InputEventPanGesture).delta * Bindings.TRACKPAD_PAN_SPEED
	return Vector2.ZERO


## 判断输入事件是否携带指定语义修饰键（如切换多选、追加框选、临时绕过网格吸附）。
static func has_modifier(event: InputEvent, mod_role: StringName) -> bool:
	if not (event is InputEventWithModifiers):
		return false
	var em: InputEventWithModifiers = event as InputEventWithModifiers
	match mod_role:
		MOD_TOGGLE_SELECT:
			return em.is_command_or_control_pressed() or em.ctrl_pressed
		MOD_ADDITIVE_SELECT:
			return em.shift_pressed
		MOD_BYPASS_SNAP:
			return em.alt_pressed
	return false

#endregion


#region 快捷键人类可读文本格式化

## 返回指定动作在当前操作系统下的标准可读快捷键字符串（如 `"Ctrl+D"` 或 `"Cmd+D"`）。
static func format_shortcut(action: StringName) -> String:
	_ensure_init()
	if not _key_bindings.has(action):
		return ""
	var chords: Array = _key_bindings[action] as Array
	if chords.is_empty():
		return ""
	var primary: Dictionary = chords[0] as Dictionary
	var parts := PackedStringArray()
	var is_macos: bool = OS.get_name() == "macOS"
	if bool(primary.get("cmd_or_ctrl", false)):
		parts.append("Cmd" if is_macos else "Ctrl")
	if bool(primary.get("alt", false)):
		parts.append("Opt" if is_macos else "Alt")
	if bool(primary.get("shift", false)):
		parts.append("Shift")
	var k_code: Key = int(primary.get("key", 0)) as Key
	parts.append(_readable_key_name(k_code))
	return "+".join(parts)


static func _readable_key_name(k_code: Key) -> String:
	var raw: String = OS.get_keycode_string(k_code)
	if raw == "Delete":
		return "Del"
	if raw == "Escape":
		return "Esc"
	return raw

#endregion
