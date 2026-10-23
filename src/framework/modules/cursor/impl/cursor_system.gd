class_name CursorSystem
extends BaseCursorSystem

## 全局自定义鼠标指针、五层交互状态裁决与顶层粒子特效系统实现（Cursor System Orchestrator）。[br]
##
## [b]架构设计（三大单一职责微内核协同）：[/b][br]
## 1. [b][CursorStateResolver][/b]：纯逻辑五层漏斗裁决当前 `(shape, is_pressed, layer)`；[br]
## 2. [b][CursorPointerDriver][/b]：驱动 OS 硬件光标（含高分屏 DPI 自适应重采样）与画布软件光标互斥渲染；[br]
## 3. [b][CursorVfxStage][/b]：在 `Layer.CURSOR (120)` 驱动零延迟移动星尘拖尾与 8 槽位点击爆裂环形对象池。

#region Module Dependency Manifest
const MODULE_ID: StringName = &"cursor"
const REQUIRED_MODULES: Array[StringName] = []
const OPTIONAL_MODULES: Array[StringName] = [&"display", &"input", &"logger"]
#endregion

#region Injected Dependencies & Collaborators
var _display_service: BaseDisplaySystem = null
var _input_service: BaseInputSystem = null
var _logger: BaseFrameworkLogger = null

var _resolver: CursorStateResolver = CursorStateResolver.new()
var _pointer_driver: CursorPointerDriver = null
var _vfx_stage: CursorVfxStage = null
var _fallback_layer: CanvasLayer = null

var _confined_requested: bool = false
var _cursor_visible: bool = true
var _is_app_paused: bool = false
var _is_left_pressed: bool = false
var _device_type: int = InputDeviceType.Type.KEYBOARD_MOUSE

var _active_shape: int = CursorShapeType.Shape.DEFAULT
var _active_pressed: bool = false
var _active_layer_tag: String = "L1_DEFAULT"
#endregion


#region Lifecycle
func _init(
	display_service: BaseDisplaySystem = null,
	input_service: BaseInputSystem = null,
	logger: BaseFrameworkLogger = null
) -> void:
	_display_service = display_service
	_input_service = input_service
	_logger = logger


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_mount_visual_stages()
	_bind_bus_signals()
	_evaluate_and_apply(true)


func initialize() -> Result:
	_mount_visual_stages()
	_bind_bus_signals()
	_evaluate_and_apply(true)
	_log_info("CursorSystem initialized (11 semantic shapes, 5-layer resolver, hybrid pointer & VFX stage ready).")
	return Result.ok()


func dispose() -> void:
	_unbind_bus_signals()
	_resolver.clear_overrides()
	if is_instance_valid(_pointer_driver):
		_pointer_driver.queue_free()
		_pointer_driver = null
	if is_instance_valid(_vfx_stage):
		_vfx_stage.queue_free()
		_vfx_stage = null
	if is_instance_valid(_fallback_layer):
		_fallback_layer.queue_free()
		_fallback_layer = null
	if is_inside_tree():
		queue_free()


func _process(_delta: float) -> void:
	_evaluate_and_apply(false)


func _input(event: InputEvent) -> void:
	if not _cursor_visible:
		return

	if event is InputEventMouseMotion:
		var canvas_pos := _get_canvas_mouse_pos()
		if _pointer_driver != null:
			_pointer_driver.update_cursor_position(canvas_pos)
		if _vfx_stage != null:
			_vfx_stage.notify_mouse_moved(canvas_pos)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_is_left_pressed = mb.pressed
			var canvas_pos := _get_canvas_mouse_pos()
			if _pointer_driver != null:
				_pointer_driver.update_cursor_position(canvas_pos)
			if mb.pressed and _vfx_stage != null:
				_vfx_stage.trigger_click_burst(canvas_pos)
			_evaluate_and_apply(false)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_MOUSE_ENTER:
		if _pointer_driver != null:
			_pointer_driver.set_window_inside(true)
		if _vfx_stage != null:
			_vfx_stage.set_window_inside(true)
	elif what == NOTIFICATION_WM_MOUSE_EXIT:
		if _pointer_driver != null:
			_pointer_driver.set_window_inside(false)
		if _vfx_stage != null:
			_vfx_stage.set_window_inside(false)
#endregion


#region 1. Theme & Visual Mode Configuration
func set_theme(theme: CursorThemeConfig) -> void:
	if _pointer_driver != null:
		_pointer_driver.set_theme(theme)
	if _vfx_stage != null:
		_vfx_stage.apply_theme(theme)
	_evaluate_and_apply(true)


func get_theme() -> CursorThemeConfig:
	return _pointer_driver.get_theme() if _pointer_driver != null else null


func set_gameplay_cursor(shape: int) -> void:
	_resolver.set_gameplay_cursor(shape)
	_evaluate_and_apply(false)


func get_gameplay_cursor() -> int:
	return _resolver.get_gameplay_cursor()


func set_software_cursor_preferred(preferred: bool) -> void:
	if _pointer_driver != null:
		_pointer_driver.set_software_preferred(preferred)
	_evaluate_and_apply(true)


func is_using_software_cursor() -> bool:
	return _pointer_driver.is_using_software() if _pointer_driver != null else false
#endregion


#region 2. Five-Layer Interaction Cursor Switching
func push_override(token: StringName, shape: int, priority: int = 100) -> void:
	_resolver.push_override(token, shape, priority)
	_evaluate_and_apply(false)


func pop_override(token: StringName) -> void:
	_resolver.pop_override(token)
	_evaluate_and_apply(false)


func clear_overrides() -> void:
	_resolver.clear_overrides()
	_evaluate_and_apply(false)


func bind_control(control: Control, hover_shape: int, pressed_shape: int = -1) -> void:
	_resolver.bind_control(control, hover_shape, pressed_shape)
	_evaluate_and_apply(false)


func unbind_control(control: Control) -> void:
	_resolver.unbind_control(control)
	_evaluate_and_apply(false)


func bind_hover_node(node: Node, hover_shape: int, priority: int = 0) -> void:
	if not is_instance_valid(node):
		return
	var node_id := node.get_instance_id()
	var on_enter := func() -> void:
		set_world_hover(node_id, hover_shape, priority)
	var on_exit := func() -> void:
		clear_world_hover(node_id)

	if node.has_signal("mouse_entered") and not node.is_connected("mouse_entered", on_enter):
		node.connect("mouse_entered", on_enter)
	if node.has_signal("mouse_exited") and not node.is_connected("mouse_exited", on_exit):
		node.connect("mouse_exited", on_exit)
	if not node.tree_exiting.is_connected(on_exit):
		node.tree_exiting.connect(on_exit, CONNECT_ONE_SHOT)


func set_world_hover(source_id: Variant, shape: int, priority: int = 0) -> void:
	_resolver.set_world_hover(source_id, shape, priority)
	_evaluate_and_apply(false)


func clear_world_hover(source_id: Variant) -> void:
	_resolver.clear_world_hover(source_id)
	_evaluate_and_apply(false)
#endregion


#region 3. Particle VFX & Dynamic Impulse
func set_vfx_enabled(trail_enabled: bool, click_enabled: bool = true) -> void:
	if _vfx_stage != null:
		_vfx_stage.set_vfx_enabled(trail_enabled, click_enabled)


func is_trail_vfx_enabled() -> bool:
	return _vfx_stage.is_trail_enabled() if _vfx_stage != null else false


func is_click_vfx_enabled() -> bool:
	return _vfx_stage.is_click_enabled() if _vfx_stage != null else false


func pulse(scale_kick: float = 1.35, duration: float = 0.12) -> void:
	if _pointer_driver != null:
		_pointer_driver.pulse(scale_kick, duration)


func spawn_click_burst(canvas_pos: Vector2 = Vector2(-1.0, -1.0)) -> void:
	if _vfx_stage != null:
		var pos := canvas_pos if (canvas_pos.x >= 0.0 and canvas_pos.y >= 0.0) else _get_canvas_mouse_pos()
		_vfx_stage.trigger_click_burst(pos)
#endregion


#region 4. Confinement, Visibility & Diagnostics
func set_confined(confined: bool) -> void:
	if _confined_requested == confined:
		return
	_confined_requested = confined
	_sync_visibility_and_confinement()


func is_confined() -> bool:
	return _confined_requested


func is_cursor_visible() -> bool:
	return _cursor_visible


func get_current_shape() -> int:
	return _active_shape


func is_pressed_state() -> bool:
	return _active_pressed


func get_diagnostics() -> Dictionary:
	return {
		"current_shape": String(CursorShapeType.to_string_name(_active_shape)),
		"is_pressed": _active_pressed,
		"winning_layer": _active_layer_tag,
		"visible": _cursor_visible,
		"using_software_cursor": is_using_software_cursor(),
		"confined_requested": _confined_requested,
		"override_count": _resolver.get_override_count(),
		"world_hover_count": _resolver.get_world_hover_count(),
		"trail_vfx_enabled": is_trail_vfx_enabled(),
		"click_vfx_enabled": is_click_vfx_enabled(),
		"total_click_bursts": _vfx_stage.get_total_bursts_spawned() if _vfx_stage != null else 0,
	}
#endregion


#region Internal Evaluation & Synergy
func _mount_visual_stages() -> void:
	if _pointer_driver != null and _vfx_stage != null:
		return

	var target_layer: CanvasLayer = null
	if _display_service != null:
		target_layer = _display_service.get_layer(BaseDisplaySystem.Layer.CURSOR)

	if target_layer == null:
		if _fallback_layer == null:
			_fallback_layer = CanvasLayer.new()
			_fallback_layer.layer = BaseDisplaySystem.Layer.CURSOR
			_fallback_layer.name = "CursorFallbackLayer"
			add_child(_fallback_layer)
		target_layer = _fallback_layer

	_vfx_stage = CursorVfxStage.new()
	_vfx_stage.name = "CursorVfxStage"
	target_layer.add_child(_vfx_stage)

	_pointer_driver = CursorPointerDriver.new()
	_pointer_driver.name = "CursorPointerDriver"
	target_layer.add_child(_pointer_driver)


func _evaluate_and_apply(force: bool) -> void:
	if _pointer_driver == null:
		return

	var vp := get_viewport()
	var hovered_ctrl: Control = vp.gui_get_hovered_control() if vp != null else null
	var input_ctx: int = (
		_input_service.get_active_context()
		if _input_service != null
		else InputContextType.Context.GAMEPLAY
	)

	var eval_res := _resolver.evaluate(hovered_ctrl, input_ctx, _is_left_pressed)
	var new_shape: int = int(eval_res["shape"])
	var new_pressed: bool = bool(eval_res["is_pressed"])
	_active_layer_tag = str(eval_res["layer"])

	var shape_or_press_changed := (new_shape != _active_shape or new_pressed != _active_pressed)
	_active_shape = new_shape
	_active_pressed = new_pressed

	_sync_visibility_and_confinement()
	var dpi_scale := _compute_dpi_scale()
	if force or shape_or_press_changed:
		_pointer_driver.apply_state(_active_shape, _active_pressed, dpi_scale)
		if shape_or_press_changed:
			cursor_shape_changed.emit(_active_shape, _active_pressed)
	else:
		_pointer_driver.apply_state(_active_shape, _active_pressed, dpi_scale)


func _sync_visibility_and_confinement() -> void:
	if _input_service != null and _input_service.current_device == InputDeviceType.Type.JOYPAD:
		_device_type = InputDeviceType.Type.JOYPAD
	var is_joypad := (_device_type == InputDeviceType.Type.JOYPAD)
	var new_visible := not is_joypad and not OS.has_feature("mobile")
	var vis_changed := (new_visible != _cursor_visible)
	_cursor_visible = new_visible

	var in_gameplay := (
		_input_service == null
		or _input_service.get_active_context() == InputContextType.Context.GAMEPLAY
	)
	# 仅在开启了锁边、处于 GAMEPLAY 上下文、且窗口未切后台时才真正锁住鼠标边界
	var effective_confined := _confined_requested and in_gameplay and not _is_app_paused and _cursor_visible

	if _pointer_driver != null:
		_pointer_driver.apply_visibility_and_confinement(_cursor_visible, effective_confined)
	if _vfx_stage != null:
		_vfx_stage.set_master_visible(_cursor_visible)

	if vis_changed:
		cursor_visibility_changed.emit(_cursor_visible)


func _compute_dpi_scale() -> float:
	if _display_service == null:
		return 1.0
	var win_sz := Vector2(_display_service.get_resolution())
	var design_sz := _display_service.get_design_size()
	if win_sz.x <= 0.0 or win_sz.y <= 0.0 or design_sz.x <= 0.0 or design_sz.y <= 0.0:
		return 1.0
	return clampf(minf(win_sz.x / design_sz.x, win_sz.y / design_sz.y), 0.5, 4.0)


func _get_canvas_mouse_pos() -> Vector2:
	var vp := get_viewport()
	return vp.get_mouse_position() if vp != null else Vector2.ZERO


func _bind_bus_signals() -> void:
	if Bus == null:
		return
	if not Bus.input_device_changed.is_connected(_on_input_device_changed):
		Bus.input_device_changed.connect(_on_input_device_changed)
	if not Bus.app_paused.is_connected(_on_app_paused):
		Bus.app_paused.connect(_on_app_paused)
	if not Bus.app_resumed.is_connected(_on_app_resumed):
		Bus.app_resumed.connect(_on_app_resumed)


func _unbind_bus_signals() -> void:
	if Bus == null:
		return
	if Bus.input_device_changed.is_connected(_on_input_device_changed):
		Bus.input_device_changed.disconnect(_on_input_device_changed)
	if Bus.app_paused.is_connected(_on_app_paused):
		Bus.app_paused.disconnect(_on_app_paused)
	if Bus.app_resumed.is_connected(_on_app_resumed):
		Bus.app_resumed.disconnect(_on_app_resumed)


func _on_input_device_changed(device_type: int, _joy_brand: int) -> void:
	_device_type = device_type
	_sync_visibility_and_confinement()


func _on_app_paused() -> void:
	_is_app_paused = true
	_is_left_pressed = false
	_sync_visibility_and_confinement()


func _on_app_resumed() -> void:
	_is_app_paused = false
	_sync_visibility_and_confinement()


func _log_info(message: String) -> void:
	if _logger != null:
		_logger.info("Cursor", message)
	else:
		FrameworkLogger.print_raw(LogLevel.INFO, "Cursor", message)
#endregion
