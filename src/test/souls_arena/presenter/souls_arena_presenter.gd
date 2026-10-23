class_name SoulsArenaPresenter
extends RefCounted

## 3D 魂系演练场协调器（位于 src/test/souls_arena/presenter/，遵循 MSVP 的 `Presenter` 规范）。[br]
##
## [b]核心职责：[/b][br]
## 1. 连接 [SoulsArenaState]、[SoulsArenaService]、[SoulsBossAiController]、[SoulsArenaView]、[SoulsCameraRig3D] 与 3D 骑士实体；[br]
## 2. 在 `bind()` 阶段注入 `BTGraphDef` 与 `FsmGraphDef` 抽象语法树至独立蓝图弹窗并执行 6 项自动化契约验证；[br]
## 3. 将玩家 `WASD` 输入结合 [SoulsCameraRig3D] 投影为 3D 地面移动矢量，处理 `Q` 视角锁定、`H` 键位教学弹窗、`B / Tab` AST 蓝图弹窗与全套魂系招式指令。


#region 私有变量

var _view: SoulsArenaView = null
var _camera_rig: SoulsCameraRig3D = null
var _player: SoulsFighterActor = null
var _boss: SoulsFighterActor = null
var _boss_ai: SoulsBossAiController = null
var _state: SoulsArenaState = null
var _service: SoulsArenaService = null

#endregion


#region 生命周期

func _init(
	view: SoulsArenaView,
	camera_rig: SoulsCameraRig3D,
	player: SoulsFighterActor,
	boss: SoulsFighterActor
) -> void:
	_view = view
	_camera_rig = camera_rig
	_player = player
	_boss = boss
	_state = SoulsArenaState.new()
	_boss_ai = SoulsBossAiController.new(_boss, _player)
	_service = SoulsArenaService.new(_state, _player, _boss, _boss_ai)


## 绑定视图信号、初始化 3D 越肩锁定相机、注入 AST 蓝图并执行首轮 6 项契约验证。
func bind() -> void:
	_state.state_changed.connect(_on_state_changed)
	_state.log_appended.connect(_on_log_appended)
	_service.combat_banner_triggered.connect(_on_combat_banner_triggered)
	_service.camera_shake_requested.connect(_on_camera_shake_requested)

	_view.toggle_lock_on_requested.connect(_on_toggle_lock_on_requested)
	_view.toggle_keybind_help_requested.connect(_on_toggle_keybind_help_requested)
	_view.toggle_blueprint_requested.connect(_on_toggle_blueprint_requested)
	_view.reset_arena_requested.connect(_on_reset_arena_requested)
	_view.rerun_verification_requested.connect(_on_rerun_verification_requested)

	if _camera_rig != null:
		_camera_rig.setup_targets(_player, _boss, _state.is_locked_on)

	_view.bind_ast_graphs(
		_boss_ai.get_bt_graph_def(),
		_boss_ai.get_blackboard(),
		_player.get_fsm_graph_def()
	)

	_service.run_verification_suite()
	_view.render_all_logs(_state.log_lines)
	_view.render_state(_state)


## 场景退栈或销毁时彻底解绑，防止循环引用。
func unbind() -> void:
	if _state != null:
		if _state.state_changed.is_connected(_on_state_changed):
			_state.state_changed.disconnect(_on_state_changed)
		if _state.log_appended.is_connected(_on_log_appended):
			_state.log_appended.disconnect(_on_log_appended)

	if _service != null and _service.combat_banner_triggered.is_connected(_on_combat_banner_triggered):
		_service.combat_banner_triggered.disconnect(_on_combat_banner_triggered)
	if _service != null and _service.camera_shake_requested.is_connected(_on_camera_shake_requested):
		_service.camera_shake_requested.disconnect(_on_camera_shake_requested)

	if _view != null:
		_view.bind_ast_graphs(null, null, null)

	if _service != null:
		_service.cleanup_on_exit()
		_service = null

	if _boss_ai != null:
		_boss_ai.clear()
		_boss_ai = null

	_camera_rig = null
	_player = null
	_boss = null
	_view = null
	_state = null

#endregion


#region 3D 帧同步与键鼠操控处理

func tick(delta: float) -> void:
	if _service == null:
		return

	var input_xz := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A):
		input_xz.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D):
		input_xz.x += 1.0
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		input_xz.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		input_xz.y += 1.0

	var move_dir_3d := Vector3.ZERO
	if _camera_rig != null:
		move_dir_3d = _camera_rig.compute_world_move_dir(input_xz)
	elif input_xz.length_squared() > 0.001:
		move_dir_3d = Vector3(input_xz.x, 0.0, input_xz.y).normalized()

	_service.tick_arena(delta, move_dir_3d)

	if _camera_rig != null:
		_camera_rig.tick_camera(delta)


func handle_unhandled_input(event: InputEvent) -> void:
	if _service == null or _state == null:
		return

	if event is InputEventKey:
		var key_ev: InputEventKey = event as InputEventKey
		if key_ev.pressed and not key_ev.echo:
			match key_ev.physical_keycode:
				KEY_H, KEY_F1:
					_on_toggle_keybind_help_requested(not _state.is_keybind_help_open)
				KEY_B, KEY_TAB:
					_on_toggle_blueprint_requested(not _state.is_blueprint_open)
				KEY_Q:
					_on_toggle_lock_on_requested()
				KEY_ESCAPE:
					if _state.is_keybind_help_open:
						_on_toggle_keybind_help_requested(false)
					elif _state.is_blueprint_open:
						_on_toggle_blueprint_requested(false)
					else:
						_on_toggle_keybind_help_requested(true)
				KEY_SPACE:
					if not _is_any_dialog_open():
						_service.player_trigger_dodge(_player.move_dir_3d if _player != null else Vector3.ZERO)
				KEY_J, KEY_F, KEY_E:
					if not _is_any_dialog_open():
						_service.player_trigger_attack_or_riposte()
				KEY_K, KEY_C:
					if not _is_any_dialog_open():
						_service.player_trigger_parry()
				KEY_SHIFT:
					if not _is_any_dialog_open():
						_service.player_toggle_hold_shield()
				KEY_R:
					if not _is_any_dialog_open():
						_service.reset_arena_positions()
		elif not key_ev.pressed:
			if key_ev.physical_keycode in [KEY_K, KEY_C]:
				_service.player_release_shield()

	elif event is InputEventMouseButton and not _is_any_dialog_open():
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_service.player_trigger_attack_or_riposte()
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			if mb.pressed:
				_service.player_trigger_parry()
			else:
				_service.player_release_shield()
		elif mb.button_index == MOUSE_BUTTON_MIDDLE and mb.pressed:
			_on_toggle_lock_on_requested()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			if _camera_rig != null:
				_camera_rig.adjust_zoom(-0.55)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			if _camera_rig != null:
				_camera_rig.adjust_zoom(0.55)
	elif event is InputEventMouseMotion and not _is_any_dialog_open():
		var mm: InputEventMouseMotion = event as InputEventMouseMotion
		if _camera_rig != null and not _camera_rig.is_locked_on():
			_camera_rig.rotate_free_yaw(-mm.relative.x * 0.0045)


func _is_any_dialog_open() -> bool:
	if _state == null:
		return false
	return _state.is_keybind_help_open or _state.is_blueprint_open

#endregion


#region 内部信号回调

func _on_state_changed() -> void:
	if _view != null and _state != null:
		_view.render_state(_state)


func _on_log_appended(bbcode_line: String) -> void:
	if _view != null:
		_view.append_log_line(bbcode_line)


func _on_combat_banner_triggered(bbcode_text: String) -> void:
	if _view != null:
		_view.show_combat_banner(bbcode_text, 1.8)


func _on_camera_shake_requested(intensity: float, duration: float, fov_kick: float) -> void:
	if _camera_rig != null:
		_camera_rig.trigger_impact_shake(intensity, duration, fov_kick)


func _on_toggle_lock_on_requested() -> void:
	if _service == null:
		return
	var locked: bool = _service.toggle_lock_on()
	if _camera_rig != null:
		_camera_rig.set_locked_on(locked)


func _on_toggle_keybind_help_requested(open: bool) -> void:
	if _service != null:
		_service.set_keybind_help_open(open)


func _on_toggle_blueprint_requested(open: bool) -> void:
	if _service != null:
		_service.set_blueprint_open(open)


func _on_reset_arena_requested() -> void:
	if _service != null:
		_service.reset_arena_positions()


func _on_rerun_verification_requested() -> void:
	if _service != null and _view != null and _state != null:
		_state.log_lines.clear()
		_view.render_all_logs(_state.log_lines)
		_service.run_verification_suite()

#endregion
