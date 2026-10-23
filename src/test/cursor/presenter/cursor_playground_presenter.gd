class_name CursorPlaygroundPresenter
extends RefCounted

## 自定义鼠标教学演练场协调器（位于 src/test/cursor/presenter/，遵循 MSVP 的 `Presenter` 规范）。[br]
##
## [b]核心职责：[/b][br]
## 1. 连接 [CursorTestState]、[CursorTestService] 与 [CursorPlaygroundView]；[br]
## 2. 在 `bind()` 阶段完成 UI 靶标控件的声明式光标绑定（`App.cursor.bind_control`）与 6 项契约自检；[br]
## 3. 监听 `App.cursor.cursor_shape_changed` 信号与帧同步，实时刷新顶部五层漏斗诊断状态栏。


#region 私有变量

var _host_scene: Node = null
var _view: CursorPlaygroundView = null
var _state: CursorTestState = null
var _service: CursorTestService = null

#endregion


#region 生命周期

func _init(host_scene: Node, view: CursorPlaygroundView) -> void:
	_host_scene = host_scene
	_view = view
	_state = CursorTestState.new()
	_service = CursorTestService.new(_state)


## 绑定视图信号、注册控件光标语义并执行首轮契约验证。
func bind() -> void:
	_state.state_changed.connect(_on_state_changed)
	_state.log_appended.connect(_on_log_appended)

	_view.theme_preset_selected.connect(_on_theme_preset_selected)
	_view.toggle_gameplay_cursor_requested.connect(_on_toggle_gameplay_cursor_requested)
	_view.toggle_wait_override_requested.connect(_on_toggle_wait_override_requested)
	_view.toggle_software_mode_requested.connect(_on_toggle_software_mode_requested)
	_view.trigger_recoil_pulse_requested.connect(_on_trigger_recoil_pulse_requested)
	_view.toggle_trail_vfx_requested.connect(_on_toggle_trail_vfx_requested)
	_view.toggle_click_vfx_requested.connect(_on_toggle_click_vfx_requested)
	_view.toggle_confinement_requested.connect(_on_toggle_confinement_requested)
	_view.rerun_verification_requested.connect(_on_rerun_verification_requested)

	if App != null and App.cursor != null:
		if not App.cursor.cursor_shape_changed.is_connected(_on_cursor_shape_changed):
			App.cursor.cursor_shape_changed.connect(_on_cursor_shape_changed)
		if not App.cursor.cursor_visibility_changed.is_connected(_on_cursor_visibility_changed):
			App.cursor.cursor_visibility_changed.connect(_on_cursor_visibility_changed)

	_register_declarative_control_cursors()

	# 默认进入演练场时挂载「赛博青白主题」并执行 6 项自动化契约验证
	_service.apply_theme_preset(CursorTestState.ThemePreset.CYBER_PROCEDURAL)
	_service.run_verification_suite(_host_scene)
	_view.render_all_logs(_state.log_lines)
	_view.render_state(_state)


## 场景退栈/销毁时解绑监听并清理全局覆盖状态。
func unbind() -> void:
	if App != null and App.cursor != null:
		if App.cursor.cursor_shape_changed.is_connected(_on_cursor_shape_changed):
			App.cursor.cursor_shape_changed.disconnect(_on_cursor_shape_changed)
		if App.cursor.cursor_visibility_changed.is_connected(_on_cursor_visibility_changed):
			App.cursor.cursor_visibility_changed.disconnect(_on_cursor_visibility_changed)

	if _state != null:
		if _state.state_changed.is_connected(_on_state_changed):
			_state.state_changed.disconnect(_on_state_changed)
		if _state.log_appended.is_connected(_on_log_appended):
			_state.log_appended.disconnect(_on_log_appended)

	if _service != null:
		_service.cleanup_on_exit()

	_view = null
	_service = null
	_state = null
	_host_scene = null


## 帧级轻量巡检：当按压状态或胜出层级发生变化时同步刷新状态栏。
func poll_live_diagnostics() -> void:
	if _state == null or App == null or App.cursor == null:
		return
	var current_pressed: bool = App.cursor.is_pressed_state()
	var current_shape: int = App.cursor.get_current_shape()
	if current_pressed != _state.is_pressed or current_shape != _state.active_shape:
		_state.sync_from_cursor_system()

#endregion


#region 内部绑定与事件回调

## 演示如何通过一行 `App.cursor.bind_control(control, shape)` 为特定控件声明式绑定自定义光标。
func _register_declarative_control_cursors() -> void:
	if _view == null or _service == null:
		return
	# L4 UI 特殊控件绑定
	_service.bind_ui_control_cursor(_view.get_grab_card_btn(), CursorShapeType.Shape.GRAB)
	_service.bind_ui_control_cursor(_view.get_help_tip_btn(), CursorShapeType.Shape.HELP)

	# 局内世界/语义交互靶标绑定
	_service.bind_ui_control_cursor(_view.get_target_interact_btn(), CursorShapeType.Shape.INTERACT)
	_service.bind_ui_control_cursor(_view.get_target_attack_btn(), CursorShapeType.Shape.ATTACK)
	_service.bind_ui_control_cursor(_view.get_target_crosshair_btn(), CursorShapeType.Shape.CROSSHAIR)
	_service.bind_ui_control_cursor(_view.get_target_zoom_in_btn(), CursorShapeType.Shape.ZOOM_IN)
	_service.bind_ui_control_cursor(_view.get_target_zoom_out_btn(), CursorShapeType.Shape.ZOOM_OUT)


func _on_state_changed() -> void:
	if _view != null and _state != null:
		_view.render_state(_state)


func _on_log_appended(bbcode_line: String) -> void:
	if _view != null:
		_view.append_log_line(bbcode_line)


func _on_cursor_shape_changed(_new_shape: int, _is_pressed: bool) -> void:
	if _state != null:
		_state.sync_from_cursor_system()


func _on_cursor_visibility_changed(_visible: bool) -> void:
	if _state != null:
		_state.sync_from_cursor_system()


func _on_theme_preset_selected(preset_id: int) -> void:
	if _service != null:
		_service.apply_theme_preset(preset_id)


func _on_toggle_gameplay_cursor_requested() -> void:
	if _service != null:
		_service.toggle_gameplay_cursor()


func _on_toggle_wait_override_requested() -> void:
	if _service != null:
		_service.toggle_wait_override()


func _on_toggle_software_mode_requested() -> void:
	if _service != null:
		_service.toggle_software_cursor_mode()


func _on_trigger_recoil_pulse_requested() -> void:
	if _service != null:
		_service.trigger_recoil_pulse()


func _on_toggle_trail_vfx_requested() -> void:
	if _service != null:
		_service.toggle_trail_vfx()


func _on_toggle_click_vfx_requested() -> void:
	if _service != null:
		_service.toggle_click_vfx()


func _on_toggle_confinement_requested() -> void:
	if _service != null:
		_service.toggle_confinement()


func _on_rerun_verification_requested() -> void:
	if _service != null and _host_scene != null and _view != null:
		_view.render_all_logs(PackedStringArray())
		_service.run_verification_suite(_host_scene)

#endregion
