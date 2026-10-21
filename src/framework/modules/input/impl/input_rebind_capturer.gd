class_name InputRebindCapturer
extends RefCounted

## 二段式交互按键录制状态机（Two-Phase Smart Rebind Capturer）。[br]
##
## 核心体验解决：[br]
## - [b]免勾选框兼容单键与组合键[/b]：[br]
##   1. 直接按下非修饰主键（如 Q / 鼠标右键 / 手柄 A）$\rightarrow$ [b]0ms 立即完成单键录制[/b]；[br]
##   2. 按下候选修饰键（键盘 Ctrl/Shift/Alt/Meta 或手柄 LB/RB/LT/RT）$\rightarrow$ 进入 [code]HOLDING_MODIFIER[/code] 态并实时发射 [signal rebind_preview_changed]（UI 显示 [code]"Shift + ..."[/code]）；[br]
##   3. 未松开修饰键期间按下另一主键 $\rightarrow$ [b]立即合成组合键[/b]（如 [code]Shift + Q[/code] / [code]LB + A[/code]）；[br]
##   4. 未按其它键直接松开该修饰键 $\rightarrow$ [b]确认为独立单键[/b]（如单键 [code]Shift[/code] / 单键 [code]LB[/code]）。[br]
## - [b]防输入穿透吞没[/b]：录制期间与结束后首帧拦截 Viewport 输入，杜绝按 ESC 取消录制时误关设置弹窗。

signal rebind_preview_changed(preview_glyph: InputGlyphInfo)
signal rebind_finished(result: Result)

enum State {
	IDLE = 0,
	LISTENING = 1,
	HOLDING_MODIFIER = 2,
}

## 手柄扳机轴（LT/RT）或摇杆在录制时判定为有效按下的阈值
const AXIS_CAPTURE_THRESHOLD: float = 0.60

var _state: int = State.IDLE
var _target_action: StringName = &""
var _target_device: int = InputDeviceType.Type.KEYBOARD_MOUSE
var _held_modifiers: Array[InputEvent] = []
var _held_axis_signatures: Dictionary = {}
var _remaining_sec: float = 0.0


## 当前是否正在进行按键录制
func is_capturing() -> bool:
	return _state != State.IDLE


## 获取当前录制的目标设备大类
func get_target_device() -> int:
	return _target_device


## 启动一次交互式按键录制
func start_capture(action: StringName, device_type: int, timeout_sec: float = 5.0) -> Result:
	if is_capturing():
		return Result.err_code(InputError.REBIND_BUSY, "Another key rebind session is already active.")
	_state = State.LISTENING
	_target_action = action
	_target_device = device_type
	_held_modifiers.clear()
	_held_axis_signatures.clear()
	_remaining_sec = maxf(timeout_sec, 0.5)
	return Result.ok()


## 外部主动取消录制
func cancel_capture() -> void:
	if not is_capturing():
		return
	_finish(Result.err_code(InputError.REBIND_CANCELED, "Key rebinding was canceled."))


## 帧驱动更新（处理录制超时倒计时）
func tick(delta: float) -> void:
	if not is_capturing():
		return
	_remaining_sec -= delta
	if _remaining_sec <= 0.0:
		_finish(Result.err_code(InputError.REBIND_TIMEOUT, "Key rebinding timed out."))


## 拦截并处理录制期间的原始 [InputEvent]。返回 true 表示事件已被录制器消费。
func handle_input_event(event: InputEvent, joy_brand: int = InputDeviceType.JoyBrand.XBOX) -> bool:
	if not is_capturing():
		return false

	# 忽略鼠标移动与回声事件
	if event is InputEventMouseMotion:
		return false
	if event is InputEventKey and (event as InputEventKey).echo:
		return true

	# 1. 全局取消键判定：键盘 ESC 或手柄 Back/Select 键直接取消录制
	if event is InputEventKey:
		var k := event as InputEventKey
		var code := InputChord.get_canonical_keycode(k)
		if code == KEY_ESCAPE and k.pressed:
			_finish(Result.err_code(InputError.REBIND_CANCELED, "Canceled by Escape key."))
			return true
	if event is InputEventJoypadButton:
		var jb := event as InputEventJoypadButton
		if jb.button_index == JOY_BUTTON_BACK and jb.pressed:
			_finish(Result.err_code(InputError.REBIND_CANCELED, "Canceled by Joypad Back button."))
			return true

	# 2. 过滤非目标设备轨道的输入（例如正在改键盘键位时忽略手柄误碰，反之亦然）
	var ev_device := InputChord.get_event_device_type(event)
	if ev_device != _target_device:
		return true

	# 3. 将摇杆/扳机连续轴事件转化为离散的按下/松开语义
	if event is InputEventJoypadMotion:
		return _handle_joy_motion(event as InputEventJoypadMotion, joy_brand)

	# 4. 处理键盘按键、鼠标按键、手柄按钮的按下与松开
	var is_pressed := event.is_pressed()
	var clean_ev := InputChord.clean_single_event(event)
	if clean_ev == null:
		return true

	if is_pressed:
		_on_candidate_pressed(clean_ev, joy_brand)
	else:
		_on_candidate_released(clean_ev)

	return true


func _handle_joy_motion(motion: InputEventJoypadMotion, joy_brand: int) -> bool:
	var axis_key := int(motion.axis)
	var abs_val := absf(motion.axis_value)
	var was_active: bool = _held_axis_signatures.get(axis_key, false)

	if abs_val >= AXIS_CAPTURE_THRESHOLD and not was_active:
		_held_axis_signatures[axis_key] = true
		var clean_axis := InputChord.make_joy_axis_event(motion.axis, 1.0 if motion.axis_value >= 0.0 else -1.0)
		_on_candidate_pressed(clean_axis, joy_brand)
	elif abs_val < 0.25 and was_active:
		_held_axis_signatures.erase(axis_key)
		var released_axis := InputChord.make_joy_axis_event(motion.axis, 1.0)
		_on_candidate_released(released_axis)
	return true


func _on_candidate_pressed(clean_ev: InputEvent, joy_brand: int) -> void:
	var is_mod := InputChord.is_candidate_modifier_event(clean_ev)
	var max_mods := 2 if _target_device == InputDeviceType.Type.KEYBOARD_MOUSE else 1

	# 若按下的是候选修饰键，且当前暂存修饰键未达上限，进入 HOLDING_MODIFIER 等待态
	if is_mod and _held_modifiers.size() < max_mods:
		var sig := InputChord.get_single_event_signature(clean_ev)
		var already_held := false
		for m in _held_modifiers:
			if InputChord.get_single_event_signature(m) == sig:
				already_held = true
				break
		if not already_held:
			_held_modifiers.append(clean_ev)
		_state = State.HOLDING_MODIFIER
		var preview := InputGlyphInfo.from_pending_modifiers(_held_modifiers, _target_action, _target_device, joy_brand)
		rebind_preview_changed.emit(preview)
		return

	# 若按下的是普通触发主键（或第 N+1 个修饰键作为触发键），立即合成 InputChord 完成绑定！
	var chord := InputChord.from_chord(_held_modifiers, clean_ev)
	_finish(Result.ok(chord))


func _on_candidate_released(clean_ev: InputEvent) -> void:
	if _state != State.HOLDING_MODIFIER or _held_modifiers.is_empty():
		return
	# 玩家按住修饰键后未按任何其它主键便直接松开 -> 将最先按下的修饰键作为独立单键完成绑定！
	var released_sig := InputChord.get_single_event_signature(clean_ev)
	for m in _held_modifiers:
		var mod_sig := InputChord.get_single_event_signature(m)
		if mod_sig == released_sig or (clean_ev is InputEventJoypadMotion and m is InputEventJoypadMotion and (clean_ev as InputEventJoypadMotion).axis == (m as InputEventJoypadMotion).axis):
			var single_chord := InputChord.from_event(m)
			_finish(Result.ok(single_chord))
			return


func _finish(res: Result) -> void:
	_state = State.IDLE
	_held_modifiers.clear()
	_held_axis_signatures.clear()
	rebind_finished.emit(res)
