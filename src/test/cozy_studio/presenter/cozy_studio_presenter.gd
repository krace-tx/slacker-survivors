class_name CozyStudioPresenter
extends RefCounted

## 2.5D 温馨工作室交互协调器（管理三段式跟随相机、正/侧/背 3 视图相对朝向解算与序列帧角色移动）。

var _state: CozyStudioState = null
var _service: CozyStudioService = null
var _view: CozyStudioView = null
var _stage: CozyStudioStage3D = null
var _camera_rig: CozyCameraRig3D = null
var _player_actor: CozyStandeeActor3D = null
var _partner_actor: CozyStandeeActor3D = null
var _last_facing_label: String = ""


func _init(
	view: CozyStudioView,
	stage: CozyStudioStage3D,
	camera_rig: CozyCameraRig3D,
	player_actor: CozyStandeeActor3D,
	partner_actor: CozyStandeeActor3D
) -> void:
	_state = CozyStudioState.new()
	_service = CozyStudioService.new()
	_view = view
	_stage = stage
	_camera_rig = camera_rig
	_player_actor = player_actor
	_partner_actor = partner_actor


func bind() -> void:
	if _view != null:
		_view.follow_camera_toggled.connect(_on_toggle_follow_camera)
		_view.camera_mode_cycled.connect(_on_cycle_camera_mode)
		_view.lighting_mood_toggled.connect(_on_toggle_lighting_mood)
		_view.glue_layer_toggled.connect(_on_toggle_glue_layer)
		_view.reset_requested.connect(_on_reset_requested)
	if _camera_rig != null:
		_camera_rig.yaw_changed.connect(_on_camera_yaw_changed)

	_apply_all_states(true)


func unbind() -> void:
	_view = null
	_stage = null
	_camera_rig = null
	_player_actor = null
	_partner_actor = null


func tick(delta: float) -> void:
	if _player_actor == null:
		return

	# 1. Q / E 连续丝滑旋转镜头偏航角
	var yaw_input: float = 0.0
	if Input.is_physical_key_pressed(KEY_E):
		yaw_input += 1.0
	if Input.is_physical_key_pressed(KEY_Q):
		yaw_input -= 1.0

	# 2. WASD / 方向键实时绑定当前 CameraRig 偏航角：S=正视图朝向镜头、W=背视图背对镜头、A/D=侧视图左右翻转
	var raw_x: float = 0.0
	var raw_y: float = 0.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		raw_x += 1.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		raw_x -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		raw_y += 1.0
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		raw_y -= 1.0

	var input_vec := Vector2(raw_x, raw_y)
	var has_move_input: bool = input_vec.length_squared() > 0.001
	var world_velocity := Vector3.ZERO
	var actual_speed_ratio: float = 0.0

	if has_move_input and delta > 0.0001:
		input_vec = input_vec.normalized()
		var yaw_rad: float = _camera_rig.get_yaw_rad() if _camera_rig != null else deg_to_rad(37.0)
		var right_3d := Vector3(cos(yaw_rad), 0.0, -sin(yaw_rad))
		var down_3d := Vector3(sin(yaw_rad), 0.0, cos(yaw_rad))
		var move_dir: Vector3 = (right_3d * input_vec.x + down_3d * input_vec.y).normalized()

		# 更新角色在 3D 世界中的真实朝向向量，由 CozyStandeeActor3D 自动解算 正/侧/背 3 视图与左右翻转！
		_state.world_facing_dir = move_dir
		_player_actor.set_world_facing_direction(_state.world_facing_dir)

		var prev_pos: Vector3 = _state.player_pos
		var next_pos: Vector3 = prev_pos + move_dir * (CozyStudioService.MOVE_SPEED * delta)
		_state.player_pos = _service.resolve_walk_position(prev_pos, next_pos)
		_player_actor.position = _state.player_pos

		world_velocity = (_state.player_pos - prev_pos) / delta
		actual_speed_ratio = world_velocity.length() / CozyStudioService.MOVE_SPEED

	var is_actually_walking: bool = has_move_input and actual_speed_ratio > 0.05
	_player_actor.tick_visual(delta, is_actually_walking, actual_speed_ratio)
	if _partner_actor != null:
		_partner_actor.tick_visual(delta, false, 0.0)

	if _camera_rig != null:
		_camera_rig.tick_rig(delta, _state.player_pos, world_velocity, yaw_input)

	var cur_label: String = _player_actor.get_facing_view_label()
	if cur_label != _last_facing_label:
		_last_facing_label = cur_label
		_sync_hud()


func handle_unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.pressed and _camera_rig != null:
			if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
				_camera_rig.adjust_zoom(-0.65)
			elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_camera_rig.adjust_zoom(0.65)
		return

	if not (event is InputEventKey):
		return
	var key_ev: InputEventKey = event as InputEventKey
	if not key_ev.pressed or key_ev.echo:
		return

	match key_ev.physical_keycode:
		KEY_F:
			_on_toggle_follow_camera()
		KEY_1:
			_set_camera_mode(CozyStudioState.CameraMode.TELEPHOTO_25)
		KEY_2:
			_set_camera_mode(CozyStudioState.CameraMode.ORTHO_DIORAMA)
		KEY_3:
			_set_camera_mode(CozyStudioState.CameraMode.WIDE_70_COMPARE)
		KEY_L:
			_on_toggle_lighting_mood()
		KEY_G:
			_on_toggle_glue_layer()
		KEY_R:
			_on_reset_requested()


func _on_toggle_follow_camera() -> void:
	_state.follow_camera = not _state.follow_camera
	if _camera_rig != null:
		_camera_rig.set_follow_enabled(_state.follow_camera, _state.player_pos, false)
	_sync_hud()


func _on_cycle_camera_mode() -> void:
	var next_idx: int = (int(_state.camera_mode) + 1) % 3
	_set_camera_mode(next_idx as CozyStudioState.CameraMode)


func _set_camera_mode(mode: CozyStudioState.CameraMode) -> void:
	_state.camera_mode = mode
	if _camera_rig != null:
		_camera_rig.set_camera_mode(mode, false)
		_sync_actors_coplanar(_camera_rig.get_yaw_deg())
	_sync_hud()


func _on_camera_yaw_changed(yaw_deg: float) -> void:
	_sync_actors_coplanar(yaw_deg)


func _sync_actors_coplanar(yaw_deg: float) -> void:
	var tilt_deg: float = _camera_rig.get_standee_tilt_deg() if _camera_rig != null else -22.0
	if _player_actor != null:
		_player_actor.set_camera_alignment(yaw_deg, tilt_deg)
	if _partner_actor != null:
		_partner_actor.set_camera_alignment(yaw_deg, tilt_deg)


func _on_toggle_lighting_mood() -> void:
	_state.lighting_mood = (
		CozyStudioState.LightingMood.COZY_EVENING
		if _state.lighting_mood == CozyStudioState.LightingMood.AFTERNOON_SUN
		else CozyStudioState.LightingMood.AFTERNOON_SUN
	)
	if _stage != null:
		_stage.apply_lighting_mood(_state.lighting_mood, _state.glue_enabled)
	_sync_hud()


func _on_toggle_glue_layer() -> void:
	_state.glue_enabled = not _state.glue_enabled
	if _stage != null:
		_stage.apply_lighting_mood(_state.lighting_mood, _state.glue_enabled)
	if _camera_rig != null:
		_camera_rig.set_anime_outline_enabled(_state.glue_enabled)
	if _player_actor != null:
		_player_actor.set_glue_layer_enabled(_state.glue_enabled)
	if _partner_actor != null:
		_partner_actor.set_glue_layer_enabled(_state.glue_enabled)
	_sync_hud()


func _on_reset_requested() -> void:
	_state.camera_mode = CozyStudioState.CameraMode.TELEPHOTO_25
	_state.lighting_mood = CozyStudioState.LightingMood.AFTERNOON_SUN
	_state.follow_camera = true
	_state.glue_enabled = true
	_state.player_pos = CozyStudioService.PLAYER_SPAWN
	_state.world_facing_dir = Vector3(sin(deg_to_rad(37.0)), 0.0, cos(deg_to_rad(37.0)))
	if _camera_rig != null:
		_camera_rig.reset_rig(_state.player_pos)
	_apply_all_states(true)


func _apply_all_states(immediate: bool) -> void:
	if _player_actor != null:
		_player_actor.position = _state.player_pos
		_player_actor.set_world_facing_direction(_state.world_facing_dir)
		_player_actor.set_glue_layer_enabled(_state.glue_enabled)
	if _partner_actor != null:
		_partner_actor.position = CozyStudioService.PARTNER_SPAWN
		_partner_actor.set_glue_layer_enabled(_state.glue_enabled)
	if _stage != null:
		_stage.apply_lighting_mood(_state.lighting_mood, _state.glue_enabled)
		if _camera_rig != null and _stage.get_stage_environment() != null:
			_camera_rig.set_stage_environment(_stage.get_stage_environment())
	if _camera_rig != null:
		_camera_rig.set_anime_outline_enabled(_state.glue_enabled)
		_camera_rig.set_follow_enabled(_state.follow_camera, _state.player_pos, immediate)
		_camera_rig.set_camera_mode(_state.camera_mode, immediate)
		_sync_actors_coplanar(_camera_rig.get_yaw_deg())
	_last_facing_label = _player_actor.get_facing_view_label() if _player_actor != null else ""
	_sync_hud()


func _sync_hud() -> void:
	if _view != null:
		var view_label: String = _player_actor.get_facing_view_label() if _player_actor != null else "正视图"
		_view.render_hud(
			_state.follow_camera,
			_service.get_camera_mode_label(_state.camera_mode),
			_service.get_lighting_mood_label(_state.lighting_mood),
			_state.glue_enabled,
			view_label
		)
