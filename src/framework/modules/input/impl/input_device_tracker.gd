class_name InputDeviceTracker
extends RefCounted

## 物理输入设备嗅探与手柄热插拔追踪器（Input Device & Hotplug Tracker）。[br]
##
## 核心防御特性：[br]
## - [b]双阈值迟滞防抖（Hysteresis）[/b]：常规摇杆死区默认 0.2，但触发“从键鼠切换到手柄”的摇杆唤醒阈值设为 [constant JOY_WAKE_AXIS_THRESHOLD] (0.5)，彻底杜绝摇杆微漂移或磁轴键盘底噪导致 UI 图标闪烁；[br]
## - [b]手柄品牌自动识别[/b]：根据设备名称与 GUID 自动识别 Xbox / PlayStation / Switch / SteamDeck；[br]
## - [b]最后活跃手柄锁定[/b]：多外设并存时锁定最后发生实质交互的 [member active_joy_id]，供震动与轴向读取精准路由。

signal device_changed(device_type: int, joy_brand: int, joy_id: int)
signal joypad_connection_changed(device_id: int, connected: bool)

## 触发从键鼠切往手柄的摇杆大幅推动阈值（高于普通死区以过滤硬件漂移）
const JOY_WAKE_AXIS_THRESHOLD: float = 0.50

## 触发从手柄切往键鼠的鼠标单帧移动像素阈值（过滤桌面轻微震动引起的鼠标微移）
const MOUSE_WAKE_DISTANCE_PX: float = 24.0

var current_device: int = InputDeviceType.Type.KEYBOARD_MOUSE
var current_joy_brand: int = InputDeviceType.JoyBrand.XBOX
var active_joy_id: int = 0
var _connected: bool = false


func initialize() -> void:
	if not _connected:
		Input.joy_connection_changed.connect(_on_joy_connection_changed)
		_connected = true
	var pads := Input.get_connected_joypads()
	if not pads.is_empty():
		active_joy_id = pads[0]
		current_joy_brand = _detect_brand_for_device(active_joy_id)


func dispose() -> void:
	if _connected and Input.joy_connection_changed.is_connected(_on_joy_connection_changed):
		Input.joy_connection_changed.disconnect(_on_joy_connection_changed)
	_connected = false


## 处理来自引擎 _input 的原始硬件事件，判断是否发生了设备类型或手柄型号切换
func process_input_event(event: InputEvent) -> void:
	if event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo:
			_switch_to_keyboard_mouse()
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			_switch_to_keyboard_mouse()
		return

	if event is InputEventMouseMotion:
		if current_device == InputDeviceType.Type.JOYPAD:
			var mm := event as InputEventMouseMotion
			if mm.relative.length() >= MOUSE_WAKE_DISTANCE_PX:
				_switch_to_keyboard_mouse()
		return

	if event is InputEventJoypadButton:
		var jb := event as InputEventJoypadButton
		if jb.pressed:
			_switch_to_joypad(jb.device if jb.device >= 0 else 0)
		return

	if event is InputEventJoypadMotion:
		var jm := event as InputEventJoypadMotion
		if absf(jm.axis_value) >= JOY_WAKE_AXIS_THRESHOLD:
			_switch_to_joypad(jm.device if jm.device >= 0 else 0)
		return


## 手动切换或模拟当前活跃设备与手柄品牌（用于设置预览或无物理手柄调试）
func set_Simulated_device(device_type: int, joy_brand: int = -1, joy_id: int = 0) -> void:
	var new_brand := joy_brand if joy_brand >= 0 else current_joy_brand
	var changed := (current_device != device_type) or (current_joy_brand != new_brand) or (active_joy_id != joy_id)
	current_device = device_type
	current_joy_brand = new_brand
	active_joy_id = joy_id
	if changed:
		device_changed.emit(current_device, current_joy_brand, active_joy_id)


func _switch_to_keyboard_mouse() -> void:
	if current_device == InputDeviceType.Type.KEYBOARD_MOUSE:
		return
	current_device = InputDeviceType.Type.KEYBOARD_MOUSE
	device_changed.emit(current_device, current_joy_brand, active_joy_id)


func _switch_to_joypad(joy_id: int) -> void:
	var detected_brand := _detect_brand_for_device(joy_id)
	var changed := (current_device != InputDeviceType.Type.JOYPAD) or (current_joy_brand != detected_brand) or (active_joy_id != joy_id)
	current_device = InputDeviceType.Type.JOYPAD
	current_joy_brand = detected_brand
	active_joy_id = joy_id
	if changed:
		device_changed.emit(current_device, current_joy_brand, active_joy_id)


func _detect_brand_for_device(joy_id: int) -> int:
	var joy_name := Input.get_joy_name(joy_id)
	var joy_guid := Input.get_joy_guid(joy_id)
	if joy_name.is_empty() and joy_guid.is_empty():
		return current_joy_brand
	return InputDeviceType.detect_joy_brand(joy_name, joy_guid)


func _on_joy_connection_changed(device_id: int, connected: bool) -> void:
	if connected:
		active_joy_id = device_id
		current_joy_brand = _detect_brand_for_device(device_id)
	else:
		var remaining := Input.get_connected_joypads()
		if remaining.is_empty():
			if current_device == InputDeviceType.Type.JOYPAD:
				_switch_to_keyboard_mouse()
		elif active_joy_id == device_id:
			active_joy_id = remaining[0]
			current_joy_brand = _detect_brand_for_device(active_joy_id)
	joypad_connection_changed.emit(device_id, connected)
