class_name InputGlyphInfo
extends RefCounted

## 输入按键提示与图标语义信息对象（Input Glyph & Prompt Info VO）。[br]
##
## 供 UI 表现层渲染按键提示（如技能栏下标 [code][Shift + Q][/code]、手柄交互提示 [code][L1 + ×][/code]）：[br]
## - 内部自动通过 [method DisplayServer.keyboard_get_keycode_from_physical] 将物理扫描码转译为当前键盘布局的真实键帽字符；[br]
## - 自动按当前手柄品牌（Xbox / PlayStation / Switch / SteamDeck）映射专属按键文案与标准化图集 Key。

## 关联的逻辑动作名
var action: StringName = &""

## 所属设备大类（[enum InputDeviceType.Type]）
var device_type: int = InputDeviceType.Type.KEYBOARD_MOUSE

## 手柄品牌类型（[enum InputDeviceType.JoyBrand]）
var joy_brand: int = InputDeviceType.JoyBrand.XBOX

## 该槽位是否已有效绑定按键（若被清空则为 false）
var is_bound: bool = false

## 是否为包含前置修饰键的组合键
var is_chord: bool = false

## 按键图标标准化 Key 数组（按按键顺序排列，例如 ["kb_shift", "kb_q"] 或 ["ps_l1", "ps_cross"]）
var glyph_keys: PackedStringArray = PackedStringArray()

## 单个按键的可读短标签数组（例如 ["Shift", "Q"] 或 ["L1", "×"]）
var key_labels: PackedStringArray = PackedStringArray()

## 拼接完毕的完整可读展示文本（例如 "Shift + Q"、"L1 + ×"，未绑定时为 "未绑定" / "Unbound"）
var display_text: String = "Unbound"


#region Factory Builders
## 根据 [InputChord] 与目标手柄品牌构造展示信息
static func from_chord(
	chord: InputChord,
	p_action: StringName = &"",
	p_device_type: int = InputDeviceType.Type.KEYBOARD_MOUSE,
	p_joy_brand: int = InputDeviceType.JoyBrand.XBOX
) -> InputGlyphInfo:
	var info := InputGlyphInfo.new()
	info.action = p_action
	info.device_type = p_device_type
	info.joy_brand = p_joy_brand

	if chord == null or chord.is_empty():
		info.is_bound = false
		info.is_chord = false
		info.display_text = "Unbound"
		return info

	info.is_bound = true
	info.is_chord = chord.is_chord()
	info.device_type = chord.get_device_type()

	for mod_ev in chord.modifiers:
		info.glyph_keys.append(event_to_glyph_key(mod_ev, p_joy_brand))
		info.key_labels.append(event_to_label(mod_ev, p_joy_brand))

	info.glyph_keys.append(event_to_glyph_key(chord.trigger, p_joy_brand))
	info.key_labels.append(event_to_label(chord.trigger, p_joy_brand))
	info.display_text = " + ".join(info.key_labels)
	return info


## 构造录制等待中的实时预览信息（如按住 Shift 等待主键时显示 "Shift + ..."）
static func from_pending_modifiers(
	mods: Array[InputEvent],
	p_action: StringName,
	p_device_type: int,
	p_joy_brand: int = InputDeviceType.JoyBrand.XBOX
) -> InputGlyphInfo:
	var info := InputGlyphInfo.new()
	info.action = p_action
	info.device_type = p_device_type
	info.joy_brand = p_joy_brand
	info.is_bound = true
	info.is_chord = not mods.is_empty()

	for mod_ev in mods:
		info.glyph_keys.append(event_to_glyph_key(mod_ev, p_joy_brand))
		info.key_labels.append(event_to_label(mod_ev, p_joy_brand))

	var preview_parts := info.key_labels.duplicate()
	preview_parts.append("...")
	info.display_text = " + ".join(preview_parts)
	return info
#endregion


#region Static Glyph & Label Translators
## 将单个 [InputEvent] 转换为可读键帽文本（支持物理键码本地化转译与四大手柄品牌）
static func event_to_label(event: InputEvent, brand: int = InputDeviceType.JoyBrand.XBOX) -> String:
	if event is InputEventKey:
		var phys_code := InputChord.get_canonical_keycode(event as InputEventKey)
		var display_code := phys_code
		if DisplayServer.get_name() != "headless":
			var mapped := DisplayServer.keyboard_get_keycode_from_physical(phys_code)
			if mapped != KEY_NONE:
				display_code = mapped
		return _format_key_label(display_code)

	if event is InputEventMouseButton:
		var mb := (event as InputEventMouseButton).button_index
		match mb:
			MOUSE_BUTTON_LEFT:
				return "LMB"
			MOUSE_BUTTON_RIGHT:
				return "RMB"
			MOUSE_BUTTON_MIDDLE:
				return "MMB"
			MOUSE_BUTTON_WHEEL_UP:
				return "WheelUp"
			MOUSE_BUTTON_WHEEL_DOWN:
				return "WheelDown"
			MOUSE_BUTTON_XBUTTON1:
				return "Mouse4"
			MOUSE_BUTTON_XBUTTON2:
				return "Mouse5"
			_:
				return "Mouse%d" % int(mb)

	if event is InputEventJoypadButton:
		return _joy_button_label((event as InputEventJoypadButton).button_index, brand)

	if event is InputEventJoypadMotion:
		var m := event as InputEventJoypadMotion
		return _joy_axis_label(m.axis, m.axis_value, brand)

	return "?"


## 将单个 [InputEvent] 转换为标准化图标资源 Key（如 "kb_space"、"mouse_left"、"xbox_a"、"ps_cross"）
static func event_to_glyph_key(event: InputEvent, brand: int = InputDeviceType.JoyBrand.XBOX) -> String:
	if event is InputEventKey:
		var phys_code := InputChord.get_canonical_keycode(event as InputEventKey)
		var raw_name := OS.get_keycode_string(phys_code).to_lower().replace(" ", "_")
		return "kb_%s" % (raw_name if not raw_name.is_empty() else str(int(phys_code)))

	if event is InputEventMouseButton:
		var mb := (event as InputEventMouseButton).button_index
		match mb:
			MOUSE_BUTTON_LEFT:
				return "mouse_left"
			MOUSE_BUTTON_RIGHT:
				return "mouse_right"
			MOUSE_BUTTON_MIDDLE:
				return "mouse_middle"
			MOUSE_BUTTON_XBUTTON1:
				return "mouse_x1"
			MOUSE_BUTTON_XBUTTON2:
				return "mouse_x2"
			_:
				return "mouse_%d" % int(mb)

	var prefix := _brand_prefix(brand)
	if event is InputEventJoypadButton:
		var jb := (event as InputEventJoypadButton).button_index
		return "%s_%s" % [prefix, _joy_button_suffix(jb, brand)]

	if event is InputEventJoypadMotion:
		var m := event as InputEventJoypadMotion
		return "%s_%s" % [prefix, _joy_axis_suffix(m.axis, m.axis_value, brand)]

	return "unknown"


static func _format_key_label(code: Key) -> String:
	match code:
		KEY_CTRL:
			return "Ctrl"
		KEY_SHIFT:
			return "Shift"
		KEY_ALT:
			return "Alt"
		KEY_META:
			return "Cmd" if OS.get_name() == "macOS" else "Win"
		KEY_SPACE:
			return "Space"
		KEY_ESCAPE:
			return "Esc"
		KEY_ENTER, KEY_KP_ENTER:
			return "Enter"
		KEY_TAB:
			return "Tab"
		KEY_BACKSPACE:
			return "Backspace"
		KEY_UP:
			return "↑"
		KEY_DOWN:
			return "↓"
		KEY_LEFT:
			return "←"
		KEY_RIGHT:
			return "→"
		_:
			var s := OS.get_keycode_string(code)
			return s if not s.is_empty() else ("Key%d" % int(code))


static func _joy_button_label(btn: JoyButton, brand: int) -> String:
	match btn:
		JOY_BUTTON_A:
			match brand:
				InputDeviceType.JoyBrand.PLAYSTATION:
					return "×"
				InputDeviceType.JoyBrand.NINTENDO:
					return "B"
				_:
					return "A"
		JOY_BUTTON_B:
			match brand:
				InputDeviceType.JoyBrand.PLAYSTATION:
					return "○"
				InputDeviceType.JoyBrand.NINTENDO:
					return "A"
				_:
					return "B"
		JOY_BUTTON_X:
			match brand:
				InputDeviceType.JoyBrand.PLAYSTATION:
					return "□"
				InputDeviceType.JoyBrand.NINTENDO:
					return "Y"
				_:
					return "X"
		JOY_BUTTON_Y:
			match brand:
				InputDeviceType.JoyBrand.PLAYSTATION:
					return "△"
				InputDeviceType.JoyBrand.NINTENDO:
					return "X"
				_:
					return "Y"
		JOY_BUTTON_LEFT_SHOULDER:
			match brand:
				InputDeviceType.JoyBrand.PLAYSTATION:
					return "L1"
				InputDeviceType.JoyBrand.NINTENDO:
					return "L"
				_:
					return "LB"
		JOY_BUTTON_RIGHT_SHOULDER:
			match brand:
				InputDeviceType.JoyBrand.PLAYSTATION:
					return "R1"
				InputDeviceType.JoyBrand.NINTENDO:
					return "R"
				_:
					return "RB"
		JOY_BUTTON_BACK:
			match brand:
				InputDeviceType.JoyBrand.PLAYSTATION:
					return "Share"
				InputDeviceType.JoyBrand.NINTENDO:
					return "-"
				_:
					return "View"
		JOY_BUTTON_START:
			match brand:
				InputDeviceType.JoyBrand.PLAYSTATION:
					return "Options"
				InputDeviceType.JoyBrand.NINTENDO:
					return "+"
				_:
					return "Menu"
		JOY_BUTTON_LEFT_STICK:
			return "L3" if brand == InputDeviceType.JoyBrand.PLAYSTATION else "LS"
		JOY_BUTTON_RIGHT_STICK:
			return "R3" if brand == InputDeviceType.JoyBrand.PLAYSTATION else "RS"
		JOY_BUTTON_DPAD_UP:
			return "D-Up"
		JOY_BUTTON_DPAD_DOWN:
			return "D-Down"
		JOY_BUTTON_DPAD_LEFT:
			return "D-Left"
		JOY_BUTTON_DPAD_RIGHT:
			return "D-Right"
		_:
			return "JoyBtn%d" % int(btn)


static func _joy_axis_label(axis: JoyAxis, val: float, brand: int) -> String:
	match axis:
		JOY_AXIS_TRIGGER_LEFT:
			match brand:
				InputDeviceType.JoyBrand.PLAYSTATION:
					return "L2"
				InputDeviceType.JoyBrand.NINTENDO:
					return "ZL"
				_:
					return "LT"
		JOY_AXIS_TRIGGER_RIGHT:
			match brand:
				InputDeviceType.JoyBrand.PLAYSTATION:
					return "R2"
				InputDeviceType.JoyBrand.NINTENDO:
					return "ZR"
				_:
					return "RT"
		JOY_AXIS_LEFT_X:
			return "LStick→" if val >= 0.0 else "LStick←"
		JOY_AXIS_LEFT_Y:
			return "LStick↓" if val >= 0.0 else "LStick↑"
		JOY_AXIS_RIGHT_X:
			return "RStick→" if val >= 0.0 else "RStick←"
		JOY_AXIS_RIGHT_Y:
			return "RStick↓" if val >= 0.0 else "RStick↑"
		_:
			return "Axis%d%s" % [int(axis), "+" if val >= 0.0 else "-"]


static func _brand_prefix(brand: int) -> String:
	match brand:
		InputDeviceType.JoyBrand.PLAYSTATION:
			return "ps"
		InputDeviceType.JoyBrand.NINTENDO:
			return "switch"
		InputDeviceType.JoyBrand.STEAM_DECK:
			return "deck"
		_:
			return "xbox"


static func _joy_button_suffix(btn: JoyButton, brand: int) -> String:
	match btn:
		JOY_BUTTON_A:
			if brand == InputDeviceType.JoyBrand.PLAYSTATION:
				return "cross"
			return "b" if brand == InputDeviceType.JoyBrand.NINTENDO else "a"
		JOY_BUTTON_B:
			if brand == InputDeviceType.JoyBrand.PLAYSTATION:
				return "circle"
			return "a" if brand == InputDeviceType.JoyBrand.NINTENDO else "b"
		JOY_BUTTON_X:
			if brand == InputDeviceType.JoyBrand.PLAYSTATION:
				return "square"
			return "y" if brand == InputDeviceType.JoyBrand.NINTENDO else "x"
		JOY_BUTTON_Y:
			if brand == InputDeviceType.JoyBrand.PLAYSTATION:
				return "triangle"
			return "x" if brand == InputDeviceType.JoyBrand.NINTENDO else "y"
		JOY_BUTTON_LEFT_SHOULDER:
			return "l1" if brand == InputDeviceType.JoyBrand.PLAYSTATION else "lb"
		JOY_BUTTON_RIGHT_SHOULDER:
			return "r1" if brand == InputDeviceType.JoyBrand.PLAYSTATION else "rb"
		JOY_BUTTON_LEFT_STICK:
			return "l3" if brand == InputDeviceType.JoyBrand.PLAYSTATION else "ls"
		JOY_BUTTON_RIGHT_STICK:
			return "r3" if brand == InputDeviceType.JoyBrand.PLAYSTATION else "rs"
		JOY_BUTTON_DPAD_UP:
			return "dpad_up"
		JOY_BUTTON_DPAD_DOWN:
			return "dpad_down"
		JOY_BUTTON_DPAD_LEFT:
			return "dpad_left"
		JOY_BUTTON_DPAD_RIGHT:
			return "dpad_right"
		_:
			return "btn_%d" % int(btn)


static func _joy_axis_suffix(axis: JoyAxis, val: float, brand: int) -> String:
	match axis:
		JOY_AXIS_TRIGGER_LEFT:
			return "l2" if brand == InputDeviceType.JoyBrand.PLAYSTATION else "lt"
		JOY_AXIS_TRIGGER_RIGHT:
			return "r2" if brand == InputDeviceType.JoyBrand.PLAYSTATION else "rt"
		JOY_AXIS_LEFT_X:
			return "lstick_right" if val >= 0.0 else "lstick_left"
		JOY_AXIS_LEFT_Y:
			return "lstick_down" if val >= 0.0 else "lstick_up"
		JOY_AXIS_RIGHT_X:
			return "rstick_right" if val >= 0.0 else "rstick_left"
		JOY_AXIS_RIGHT_Y:
			return "rstick_down" if val >= 0.0 else "rstick_up"
		_:
			return "axis_%d_%s" % [int(axis), "pos" if val >= 0.0 else "neg"]
#endregion
