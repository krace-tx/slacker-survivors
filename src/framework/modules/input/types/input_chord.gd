class_name InputChord
extends RefCounted

## 统一复合键绑定单元（Input Chord / Composite Binding Unit）。[br]
##
## 将“普通单键”、“键盘修饰组合键（如 Shift + Q、Ctrl + 鼠标右键）”与“手柄肩键组合技（如 LB + A、LT + RB）”[br]
## 统一抽象为：[b]0~2 个前置修饰键 ([member modifiers]) + 1 个最终触发主键 ([member trigger])[/b]。[br]
##
## 核心能力：[br]
## - 规范化签名（[method get_signature]）：自动对修饰键排序，确保 [code]Ctrl + Shift + Q[/code] 与 [code]Shift + Ctrl + Q[/code] 等价；[br]
## - 物理硬件直读判定（[method is_pressed_now]）：跨过原生 InputMap 不支持手柄 AND 组合键的限制，直接对物理状态求值；[br]
## - 纯 Dictionary 编解码（[method to_dict] / [method from_dict]）：安全对接 [code]App.storage[/code] 存档落盘。

## 前置修饰键列表（0 ~ 2 个，如 KEY_SHIFT / KEY_CTRL 或手柄 LB / LT）
var modifiers: Array[InputEvent] = []

## 最终触发主键（1 个，如 KEY_Q / MOUSE_BUTTON_RIGHT 或手柄 JOY_BUTTON_A）
var trigger: InputEvent = null


#region Constructors
## 创建一个空的（未绑定）复合键对象
static func empty() -> InputChord:
	return InputChord.new()


## 从单个 [InputEvent] 构造。若该事件自带 Shift/Ctrl/Alt/Meta 标志位，自动拆解归一化到 [member modifiers]。
static func from_event(event: InputEvent) -> InputChord:
	var chord := InputChord.new()
	if event == null:
		return chord

	var extracted_mods: Array[InputEvent] = []
	if event is InputEventWithModifiers:
		var mod_ev := event as InputEventWithModifiers
		var self_key: int = get_canonical_keycode(event as InputEventKey) if event is InputEventKey else KEY_NONE
		if mod_ev.ctrl_pressed and self_key != KEY_CTRL:
			extracted_mods.append(make_key_event(KEY_CTRL))
		if mod_ev.shift_pressed and self_key != KEY_SHIFT:
			extracted_mods.append(make_key_event(KEY_SHIFT))
		if mod_ev.alt_pressed and self_key != KEY_ALT:
			extracted_mods.append(make_key_event(KEY_ALT))
		if mod_ev.meta_pressed and self_key != KEY_META:
			extracted_mods.append(make_key_event(KEY_META))

	chord.trigger = clean_single_event(event)
	chord.modifiers = _dedup_and_sort_modifiers(extracted_mods, chord.trigger)
	return chord


## 从显式修饰键数组与触发主键构造复合键
static func from_chord(mods: Array[InputEvent], main_trigger: InputEvent) -> InputChord:
	var chord := InputChord.new()
	if main_trigger == null:
		return chord
	chord.trigger = clean_single_event(main_trigger)
	var clean_mods: Array[InputEvent] = []
	for m in mods:
		if m != null:
			clean_mods.append(clean_single_event(m))
	chord.modifiers = _dedup_and_sort_modifiers(clean_mods, chord.trigger)
	return chord


## 快速构造一个物理键盘按键事件
static func make_key_event(physical_key: Key) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.physical_keycode = physical_key
	ev.keycode = physical_key
	ev.pressed = true
	return ev


## 快速构造一个鼠标按键事件
static func make_mouse_button_event(button_idx: MouseButton) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = button_idx
	ev.pressed = true
	return ev


## 快速构造一个手柄按钮事件
static func make_joy_button_event(button_idx: JoyButton) -> InputEventJoypadButton:
	var ev := InputEventJoypadButton.new()
	ev.button_index = button_idx
	ev.device = -1
	ev.pressed = true
	return ev


## 快速构造一个手柄半轴/扳机事件（[param axis_sign] 为 1.0 或 -1.0）
static func make_joy_axis_event(axis: JoyAxis, axis_sign: float = 1.0) -> InputEventJoypadMotion:
	var ev := InputEventJoypadMotion.new()
	ev.axis = axis
	ev.axis_value = 1.0 if axis_sign >= 0.0 else -1.0
	ev.device = -1
	return ev
#endregion


#region Queries & Signatures
## 是否为空绑定
func is_empty() -> bool:
	return trigger == null


## 是否为包含前置修饰键的组合键
func is_chord() -> bool:
	return trigger != null and not modifiers.is_empty()


## 获取组合键阶数（修饰键数量：单键为 0，单修饰组合键为 1，双修饰组合键为 2）
func get_order() -> int:
	return modifiers.size() if trigger != null else -1


## 获取该绑定所属的物理设备大类（[enum InputDeviceType.Type]）
func get_device_type() -> int:
	if trigger != null:
		return get_event_device_type(trigger)
	return InputDeviceType.Type.KEYBOARD_MOUSE


## 获取用于改键冲突比对的规范化唯一签名（如 "KB:KEY_4194325+KEY_81" 或 "JOY:BTN_9+BTN_0"）
func get_signature() -> String:
	if trigger == null:
		return "EMPTY"
	var dev_prefix := "JOY" if get_device_type() == InputDeviceType.Type.JOYPAD else "KB"
	var parts: PackedStringArray = []
	for m in modifiers:
		parts.append(get_single_event_signature(m))
	parts.append(get_single_event_signature(trigger))
	return "%s:%s" % [dev_prefix, "+".join(parts)]


## 仅获取触发主键（不含修饰键）的物理签名，用于同帧高阶组合键消费裁决
func get_trigger_signature() -> String:
	if trigger == null:
		return ""
	return get_single_event_signature(trigger)


## 深拷贝当前复合键
func duplicate_chord() -> InputChord:
	if is_empty():
		return InputChord.empty()
	var copy := InputChord.new()
	for m in modifiers:
		copy.modifiers.append(clean_single_event(m))
	copy.trigger = clean_single_event(trigger)
	return copy


## 转换为可注册进 Godot 原生 InputMap 的单个 InputEvent（供原生 API 兼容使用）
func to_godot_input_event() -> InputEvent:
	if trigger == null:
		return null
	var ev := clean_single_event(trigger)
	if ev is InputEventWithModifiers and not modifiers.is_empty():
		var mod_ev := ev as InputEventWithModifiers
		for m in modifiers:
			if m is InputEventKey:
				var k := get_canonical_keycode(m as InputEventKey)
				match k:
					KEY_CTRL:
						mod_ev.ctrl_pressed = true
					KEY_SHIFT:
						mod_ev.shift_pressed = true
					KEY_ALT:
						mod_ev.alt_pressed = true
					KEY_META:
						mod_ev.meta_pressed = true
	return ev
#endregion


#region Real-Time Hardware Polling
## 检测当前帧该复合键的【全部前置修饰键】是否均处于按住状态
func are_modifiers_pressed_now(active_joy_id: int = 0, joy_deadzone: float = 0.2) -> bool:
	for m in modifiers:
		if not is_single_event_pressed_now(m, active_joy_id, joy_deadzone):
			return false
	return true


## 检测当前帧该复合键的【触发主键】是否处于按住状态
func is_trigger_pressed_now(active_joy_id: int = 0, joy_deadzone: float = 0.2) -> bool:
	if trigger == null:
		return false
	return is_single_event_pressed_now(trigger, active_joy_id, joy_deadzone)


## 获取该绑定在当前帧的模拟轴强度（0.0 ~ 1.0，用于 get_action_strength / get_vector）
func get_strength_now(active_joy_id: int = 0, joy_deadzone: float = 0.2, ignore_modifiers: bool = false) -> float:
	if trigger == null:
		return 0.0
	if not ignore_modifiers and not are_modifiers_pressed_now(active_joy_id, joy_deadzone):
		return 0.0
	return get_single_event_strength_now(trigger, active_joy_id, joy_deadzone)
#endregion


#region Serialization (Dictionary <-> InputChord)
## 序列化为纯 Dictionary（供存档与设置比对）
func to_dict() -> Dictionary:
	if is_empty():
		return {"empty": true}
	var mod_list: Array[Dictionary] = []
	for m in modifiers:
		mod_list.append(_event_to_dict(m))
	return {
		"empty": false,
		"mods": mod_list,
		"trigger": _event_to_dict(trigger),
	}


## 从 Dictionary 反序列化恢复为 [InputChord]
static func from_dict(data: Dictionary) -> InputChord:
	if data.is_empty() or data.get("empty", false) == true:
		return InputChord.empty()
	var trig_dict: Variant = data.get("trigger", {})
	if not (trig_dict is Dictionary):
		return InputChord.empty()
	var trig_ev := _event_from_dict(trig_dict as Dictionary)
	if trig_ev == null:
		return InputChord.empty()

	var mods: Array[InputEvent] = []
	var raw_mods: Variant = data.get("mods", [])
	if raw_mods is Array:
		for item in raw_mods:
			if item is Dictionary:
				var m_ev := _event_from_dict(item as Dictionary)
				if m_ev != null:
					mods.append(m_ev)
	return InputChord.from_chord(mods, trig_ev)
#endregion


#region Static Hardware & Event Helpers
## 提取键盘事件的规范化物理键码（优先 physical_keycode，兜底 keycode）
static func get_canonical_keycode(ev: InputEventKey) -> Key:
	if ev == null:
		return KEY_NONE
	var code: Key = ev.physical_keycode if ev.physical_keycode != KEY_NONE else ev.keycode
	return code


## 判断单个事件属于键鼠轨道还是手柄轨道
static func get_event_device_type(event: InputEvent) -> int:
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		return InputDeviceType.Type.JOYPAD
	return InputDeviceType.Type.KEYBOARD_MOUSE


## 判断指定事件是否为候选修饰键（Keyboard: Ctrl/Shift/Alt/Meta；Gamepad: LB/RB/LT/RT）
static func is_candidate_modifier_event(event: InputEvent) -> bool:
	if event is InputEventKey:
		var k := get_canonical_keycode(event as InputEventKey)
		return k in [KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META]
	if event is InputEventJoypadButton:
		var btn := (event as InputEventJoypadButton).button_index
		return btn in [JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER]
	if event is InputEventJoypadMotion:
		var motion := event as InputEventJoypadMotion
		return motion.axis in [JOY_AXIS_TRIGGER_LEFT, JOY_AXIS_TRIGGER_RIGHT] and motion.axis_value > 0.0
	return false


## 剥离单个事件上的修饰位与冗余设备号，返回纯净单事件副本
static func clean_single_event(event: InputEvent) -> InputEvent:
	if event is InputEventKey:
		var src := event as InputEventKey
		return make_key_event(get_canonical_keycode(src))
	if event is InputEventMouseButton:
		var src := event as InputEventMouseButton
		return make_mouse_button_event(src.button_index)
	if event is InputEventJoypadButton:
		var src := event as InputEventJoypadButton
		return make_joy_button_event(src.button_index)
	if event is InputEventJoypadMotion:
		var src := event as InputEventJoypadMotion
		return make_joy_axis_event(src.axis, 1.0 if src.axis_value >= 0.0 else -1.0)
	return null


## 生成单个纯净事件的原子签名
static func get_single_event_signature(event: InputEvent) -> String:
	if event is InputEventKey:
		return "KEY_%d" % int(get_canonical_keycode(event as InputEventKey))
	if event is InputEventMouseButton:
		return "MB_%d" % int((event as InputEventMouseButton).button_index)
	if event is InputEventJoypadButton:
		return "JBTN_%d" % int((event as InputEventJoypadButton).button_index)
	if event is InputEventJoypadMotion:
		var m := event as InputEventJoypadMotion
		var sign_str := "+" if m.axis_value >= 0.0 else "-"
		return "JAXIS_%d_%s" % [int(m.axis), sign_str]
	return "UNKNOWN"


## 直接查询 Godot Input 单例判断单个物理事件当前是否按下
static func is_single_event_pressed_now(event: InputEvent, active_joy_id: int = 0, joy_deadzone: float = 0.2) -> bool:
	if event is InputEventKey:
		var k := get_canonical_keycode(event as InputEventKey)
		if k == KEY_NONE:
			return false
		return Input.is_physical_key_pressed(k) or Input.is_key_pressed(k)
	if event is InputEventMouseButton:
		return Input.is_mouse_button_pressed((event as InputEventMouseButton).button_index)
	if event is InputEventJoypadButton:
		var btn := (event as InputEventJoypadButton).button_index
		return _is_joy_button_pressed_any(btn, active_joy_id)
	if event is InputEventJoypadMotion:
		return get_single_event_strength_now(event, active_joy_id, joy_deadzone) > 0.5
	return false


## 直接查询单个物理事件当前的连续强度 (0.0 ~ 1.0)
static func get_single_event_strength_now(event: InputEvent, active_joy_id: int = 0, joy_deadzone: float = 0.2) -> float:
	if event is InputEventJoypadMotion:
		var m := event as InputEventJoypadMotion
		var raw := _get_joy_axis_any(m.axis, active_joy_id)
		var dz := clampf(joy_deadzone, 0.05, 0.9)
		if m.axis_value >= 0.0:
			if raw <= dz:
				return 0.0
			return clampf((raw - dz) / (1.0 - dz), 0.0, 1.0)
		else:
			if raw >= -dz:
				return 0.0
			return clampf((-raw - dz) / (1.0 - dz), 0.0, 1.0)
	return 1.0 if is_single_event_pressed_now(event, active_joy_id, joy_deadzone) else 0.0


static func _is_joy_button_pressed_any(btn: JoyButton, preferred_joy_id: int) -> bool:
	if preferred_joy_id >= 0 and Input.is_joy_button_pressed(preferred_joy_id, btn):
		return true
	for dev_id in Input.get_connected_joypads():
		if Input.is_joy_button_pressed(dev_id, btn):
			return true
	return Input.is_joy_button_pressed(0, btn)


static func _get_joy_axis_any(axis: JoyAxis, preferred_joy_id: int) -> float:
	if preferred_joy_id >= 0:
		var v := Input.get_joy_axis(preferred_joy_id, axis)
		if absf(v) > 0.01:
			return v
	for dev_id in Input.get_connected_joypads():
		var val := Input.get_joy_axis(dev_id, axis)
		if absf(val) > 0.05:
			return val
	return Input.get_joy_axis(0, axis)


static func _dedup_and_sort_modifiers(mods: Array[InputEvent], main_trigger: InputEvent) -> Array[InputEvent]:
	var trig_sig := get_single_event_signature(main_trigger) if main_trigger != null else ""
	var by_sig: Dictionary = {}
	for m in mods:
		if m == null:
			continue
		var sig := get_single_event_signature(m)
		if sig != trig_sig and not sig.is_empty():
			by_sig[sig] = m
	var sigs := by_sig.keys()
	sigs.sort()
	var sorted_mods: Array[InputEvent] = []
	for i in range(mini(sigs.size(), 2)):
		sorted_mods.append(by_sig[sigs[i]])
	return sorted_mods


static func _event_to_dict(event: InputEvent) -> Dictionary:
	if event is InputEventKey:
		return {
			"type": "key",
			"code": int(get_canonical_keycode(event as InputEventKey)),
		}
	if event is InputEventMouseButton:
		return {
			"type": "mouse_btn",
			"button": int((event as InputEventMouseButton).button_index),
		}
	if event is InputEventJoypadButton:
		return {
			"type": "joy_btn",
			"button": int((event as InputEventJoypadButton).button_index),
		}
	if event is InputEventJoypadMotion:
		var m := event as InputEventJoypadMotion
		return {
			"type": "joy_axis",
			"axis": int(m.axis),
			"sign": 1 if m.axis_value >= 0.0 else -1,
		}
	return {}


static func _event_from_dict(d: Dictionary) -> InputEvent:
	var t := str(d.get("type", ""))
	match t:
		"key":
			var code := int(d.get("code", 0)) as Key
			return make_key_event(code) if code != KEY_NONE else null
		"mouse_btn":
			var btn := int(d.get("button", 0)) as MouseButton
			return make_mouse_button_event(btn) if btn != MOUSE_BUTTON_NONE else null
		"joy_btn":
			var jbtn := int(d.get("button", -1)) as JoyButton
			return make_joy_button_event(jbtn) if jbtn >= 0 else null
		"joy_axis":
			var axis := int(d.get("axis", -1)) as JoyAxis
			var axis_sign := float(d.get("sign", 1))
			return make_joy_axis_event(axis, axis_sign) if axis >= 0 else null
		_:
			return null
#endregion
