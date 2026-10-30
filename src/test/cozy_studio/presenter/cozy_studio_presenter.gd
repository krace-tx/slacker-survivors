class_name CozyStudioPresenter
extends RefCounted

## 2.5D 温馨工作室交互协调器（管理三段式跟随相机、3 视图 4x9 序列帧移动、4 大 3D 家具邻近高亮与冲咖啡/入座/撸猫交互）。

const _E_TAP_MAX_SEC: float = 0.21

var _state: CozyStudioState = null
var _service: CozyStudioService = null
var _view: CozyStudioView = null
var _stage: CozyStudioStage3D = null
var _camera_rig: CozyCameraRig3D = null
var _player_actor: CozyStandeeActor3D = null
var _partner_actor: CozyStandeeActor3D = null
var _last_facing_label: String = ""

var _e_key_down: bool = false
var _e_hold_sec: float = 0.0
var _seat_move_grace_sec: float = 0.0
var _action_cooldown_sec: float = 0.0


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
		_view.interact_requested.connect(_try_execute_interaction)
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

	if _seat_move_grace_sec > 0.0:
		_seat_move_grace_sec = maxf(0.0, _seat_move_grace_sec - delta)
	if _action_cooldown_sec > 0.0:
		_action_cooldown_sec = maxf(0.0, _action_cooldown_sec - delta)

	# 1. 智能区分「点按 E 互动」与「长按 Q / E 旋转镜头」：
	#    - 不在交互范围内时：按 E 零延迟直接旋转镜头；
	#    - 站在家具旁或已入座时：点按 E (<0.21s) 触发互动/起身，长按 E (>=0.21s) 丝滑旋转镜头多角度观察！
	var has_interact_context: bool = (
		_state.posture_mode == CozyStudioState.PostureMode.SEATED
		or _state.hovered_spot != CozyStudioState.InteractSpotId.NONE
	)
	var yaw_input: float = 0.0
	if Input.is_physical_key_pressed(KEY_Q):
		yaw_input -= 1.0

	if Input.is_physical_key_pressed(KEY_E):
		if not _e_key_down:
			_e_key_down = true
			_e_hold_sec = 0.0
		else:
			_e_hold_sec += delta
		if not has_interact_context or _e_hold_sec >= _E_TAP_MAX_SEC:
			yaw_input += 1.0
	else:
		if _e_key_down:
			var was_quick_tap: bool = _e_hold_sec < _E_TAP_MAX_SEC
			_e_key_down = false
			_e_hold_sec = 0.0
			if was_quick_tap and has_interact_context:
				_try_execute_interaction()

	# 2. WASD / 方向键输入采集
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

	if _state.posture_mode == CozyStudioState.PostureMode.SEATED:
		# 入座状态下按 WASD 方向键即可自然抛物线跳下座椅恢复走动
		if has_move_input and _seat_move_grace_sec <= 0.0:
			_dismount_from_seat()
	elif _state.posture_mode == CozyStudioState.PostureMode.STANDING:
		if has_move_input and delta > 0.0001:
			input_vec = input_vec.normalized()
			var yaw_rad: float = _camera_rig.get_yaw_rad() if _camera_rig != null else deg_to_rad(37.0)
			var right_3d := Vector3(cos(yaw_rad), 0.0, -sin(yaw_rad))
			var down_3d := Vector3(sin(yaw_rad), 0.0, cos(yaw_rad))
			var move_dir: Vector3 = (right_3d * input_vec.x + down_3d * input_vec.y).normalized()

			_state.world_facing_dir = move_dir
			_player_actor.set_world_facing_direction(_state.world_facing_dir)

			var prev_pos: Vector3 = _state.player_pos
			var next_pos: Vector3 = prev_pos + move_dir * (CozyStudioService.MOVE_SPEED * delta)
			_state.player_pos = _service.resolve_walk_position(prev_pos, next_pos)
			_player_actor.position = _state.player_pos

			world_velocity = (_state.player_pos - prev_pos) / delta
			actual_speed_ratio = world_velocity.length() / CozyStudioService.MOVE_SPEED

	# 3. 邻近可交互 3D 家具探测与悬浮 SVG 胶囊更新
	_refresh_proximity_interaction()

	var is_actually_walking: bool = (
		_state.posture_mode == CozyStudioState.PostureMode.STANDING
		and has_move_input
		and actual_speed_ratio > 0.05
	)
	_player_actor.tick_visual(delta, is_actually_walking, actual_speed_ratio)
	if _partner_actor != null:
		_partner_actor.tick_visual(delta, false, 0.0)

	if _stage != null:
		_stage.tick_stage(delta)

	if _camera_rig != null:
		var focus_pos: Vector3 = _player_actor.position
		_camera_rig.tick_rig(delta, focus_pos, world_velocity, yaw_input)
		if _view != null and _camera_rig.get_camera() != null:
			_view.tick_view_overlay(delta, _camera_rig.get_camera())

	var cur_label: String = _player_actor.get_facing_view_label()
	if cur_label != _last_facing_label:
		_last_facing_label = cur_label
		_sync_hud()


func _refresh_proximity_interaction() -> void:
	if _state.posture_mode == CozyStudioState.PostureMode.TRANSITION_HOP:
		if _stage != null:
			_stage.set_highlighted_spot(CozyStudioState.InteractSpotId.NONE)
		if _view != null:
			_view.update_interact_prompt(CozyStudioState.InteractSpotId.NONE, Vector3.ZERO, "", false)
		return

	if _state.posture_mode == CozyStudioState.PostureMode.SEATED:
		_state.hovered_spot = _state.seated_spot
		if _stage != null:
			_stage.set_highlighted_spot(CozyStudioState.InteractSpotId.NONE)
		if _view != null:
			var p_pos: Vector3 = _service.get_spot_prompt_world_pos(_state.seated_spot, true)
			var p_txt: String = _service.get_spot_prompt_text(_state.seated_spot, true)
			_view.update_interact_prompt(_state.seated_spot, p_pos, p_txt, true)
		return

	var best: CozyStudioState.InteractSpotId = _service.find_best_interact_spot(
		_state.player_pos,
		_state.world_facing_dir
	)
	_state.hovered_spot = best
	if _stage != null:
		_stage.set_highlighted_spot(best)
	if _view != null:
		if best != CozyStudioState.InteractSpotId.NONE:
			var world_anchor: Vector3 = _service.get_spot_prompt_world_pos(best, false)
			var label_txt: String = _service.get_spot_prompt_text(best, false)
			_view.update_interact_prompt(best, world_anchor, label_txt, false)
		else:
			_view.update_interact_prompt(CozyStudioState.InteractSpotId.NONE, Vector3.ZERO, "", false)


func _try_execute_interaction() -> void:
	if _action_cooldown_sec > 0.0 or _player_actor == null:
		return
	if _state.posture_mode == CozyStudioState.PostureMode.TRANSITION_HOP:
		return

	if _state.posture_mode == CozyStudioState.PostureMode.SEATED:
		_dismount_from_seat()
		return

	var spot: CozyStudioState.InteractSpotId = _state.hovered_spot
	if spot == CozyStudioState.InteractSpotId.NONE:
		return

	var interact_facing: Vector3 = _service.get_spot_interact_facing(spot)
	_state.world_facing_dir = interact_facing

	if _service.is_seat_spot(spot):
		_mount_onto_seat(spot, interact_facing)
		return

	_action_cooldown_sec = 0.32
	_player_actor.play_cheer_hop(interact_facing)

	match spot:
		CozyStudioState.InteractSpotId.COFFEE_BAR:
			if _stage != null:
				_stage.trigger_brew_latte_reaction()
			if _view != null:
				_view.spawn_interact_bubbles(spot, _service.get_spot_bubble_origin(spot))
		CozyStudioState.InteractSpotId.SLEEPING_CAT:
			if _stage != null:
				_stage.trigger_pet_cat_reaction()
			if _view != null:
				_view.spawn_interact_bubbles(spot, _service.get_spot_bubble_origin(spot))
	_sync_hud()


func _mount_onto_seat(spot: CozyStudioState.InteractSpotId, seat_facing: Vector3) -> void:
	_state.return_floor_pos = _state.player_pos
	_state.seated_spot = spot
	_state.posture_mode = CozyStudioState.PostureMode.TRANSITION_HOP
	_seat_move_grace_sec = 0.28

	var seat_pos: Vector3 = _service.get_spot_seat_world_pos(spot)
	_player_actor.play_paper_hop_to(
		seat_pos,
		seat_facing,
		true,
		func() -> void:
			_state.posture_mode = CozyStudioState.PostureMode.SEATED
			if _stage != null:
				_stage.notify_seat_state_changed(spot, true)
			_last_facing_label = _player_actor.get_facing_view_label()
			_sync_hud()
	)


func _dismount_from_seat() -> void:
	if _state.posture_mode != CozyStudioState.PostureMode.SEATED or _player_actor == null:
		return
	var prev_spot: CozyStudioState.InteractSpotId = _state.seated_spot
	var floor_target: Vector3 = _service.get_spot_dismount_pos(prev_spot, _state.return_floor_pos)
	var out_dir: Vector3 = floor_target - _player_actor.position
	out_dir.y = 0.0
	if out_dir.length_squared() < 0.001:
		out_dir = Vector3(0.0, 0.0, 1.0)
	else:
		out_dir = out_dir.normalized()

	_state.posture_mode = CozyStudioState.PostureMode.TRANSITION_HOP
	_state.world_facing_dir = out_dir
	if _stage != null:
		_stage.notify_seat_state_changed(prev_spot, false)

	_player_actor.play_paper_hop_to(
		floor_target,
		out_dir,
		false,
		func() -> void:
			_state.player_pos = floor_target
			_state.seated_spot = CozyStudioState.InteractSpotId.NONE
			_state.posture_mode = CozyStudioState.PostureMode.STANDING
			_last_facing_label = _player_actor.get_facing_view_label()
			_sync_hud()
	)


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
		KEY_SPACE:
			_try_execute_interaction()
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
		var anchor_pos: Vector3 = _player_actor.position if _player_actor != null else _state.player_pos
		_camera_rig.set_follow_enabled(_state.follow_camera, anchor_pos, false)
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
	var tilt_deg: float = _camera_rig.get_standee_tilt_deg() if _camera_rig != null else -20.0
	if _player_actor != null:
		_player_actor.set_camera_alignment(yaw_deg, tilt_deg)
	if _partner_actor != null:
		_partner_actor.set_camera_alignment(yaw_deg, tilt_deg)
	if _stage != null:
		_stage.update_cutaway_walls(yaw_deg)


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
	if _stage != null and _state.seated_spot != CozyStudioState.InteractSpotId.NONE:
		_stage.notify_seat_state_changed(_state.seated_spot, false)
	_state.camera_mode = CozyStudioState.CameraMode.TELEPHOTO_25
	_state.lighting_mood = CozyStudioState.LightingMood.AFTERNOON_SUN
	_state.follow_camera = true
	_state.glue_enabled = true
	_state.posture_mode = CozyStudioState.PostureMode.STANDING
	_state.seated_spot = CozyStudioState.InteractSpotId.NONE
	_state.hovered_spot = CozyStudioState.InteractSpotId.NONE
	_state.player_pos = CozyStudioService.PLAYER_SPAWN
	_state.return_floor_pos = CozyStudioService.PLAYER_SPAWN
	_state.world_facing_dir = Vector3(sin(deg_to_rad(37.0)), 0.0, cos(deg_to_rad(37.0)))
	if _player_actor != null:
		_player_actor.set_seated_mode(false)
	if _camera_rig != null:
		_camera_rig.reset_rig(_state.player_pos)
	_apply_all_states(true)


func _apply_all_states(immediate: bool) -> void:
	if _player_actor != null:
		_player_actor.position = _state.player_pos
		_player_actor.set_seated_mode(false)
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
