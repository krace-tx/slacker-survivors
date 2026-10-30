class_name OtomeTerracePresenter
extends RefCounted

## 乙女向户外庭院「晴风湖畔 · 花树咖啡露台」MSVP 交互协调器（Presenter）。[br]
##
## [b]核心职责：[/b][br]
## 1. 绑定 [OtomeTerraceService] 状态流、[OtomeTerraceView] UI 信号与 [OtomeActor3D] 自动漫步到达回调；[br]
## 2. 协调 `WASD`/方向键漫步、鼠标点地漫步、点击悬浮气泡自动走近触发浪漫热点互动，以及 `Q/R` 或右键拖拽视角微旋；[br]
## 3. 将状态变更同步至男主四层 Spine 皮肤（服饰 + 微表情 + 手持道具）、3D 晴昼/落日星灯天气及近景推镜相机。

#region Dependencies & Private State
var _service: OtomeTerraceService = null
var _view: OtomeTerraceView = null
var _stage: OtomeTerraceStage3D = null
var _camera_rig: OtomeCameraRig3D = null
var _actor: OtomeActor3D = null

var _bound: bool = false
var _right_dragging: bool = false
var _screen_anchors_buf: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
#endregion


#region Lifecycle
func _init(
	service: OtomeTerraceService,
	view: OtomeTerraceView,
	stage: OtomeTerraceStage3D,
	camera_rig: OtomeCameraRig3D,
	actor: OtomeActor3D
) -> void:
	_service = service
	_view = view
	_stage = stage
	_camera_rig = camera_rig
	_actor = actor


## 建立信号绑定并执行首帧状态全量同步。
func bind() -> void:
	if _bound:
		return
	_bound = true

	if _service != null and _service.state != null:
		_service.state.changed.connect(_on_state_changed)

	if _view != null:
		_view.hotspot_clicked.connect(_on_hotspot_requested)
		_view.outfit_cycle_requested.connect(_on_outfit_cycle_requested)
		_view.expr_cycle_requested.connect(_on_expr_cycle_requested)
		_view.greet_requested.connect(_on_greet_requested)
		_view.interact_requested.connect(_on_interact_pill_requested)
		_view.weather_toggle_requested.connect(_on_weather_toggle_requested)
		_view.camera_toggle_requested.connect(_on_camera_toggle_requested)
		_view.choice_selected.connect(_on_choice_selected)

	if _actor != null:
		_actor.walk_target_reached.connect(_on_actor_walk_target_reached)

	_sync_all_visuals(false)


## 解除全部信号订阅，防止悬空回调。
func dispose() -> void:
	if not _bound:
		return
	_bound = false

	if _service != null and _service.state != null and _service.state.changed.is_connected(_on_state_changed):
		_service.state.changed.disconnect(_on_state_changed)

	if _actor != null and _actor.walk_target_reached.is_connected(_on_actor_walk_target_reached):
		_actor.walk_target_reached.disconnect(_on_actor_walk_target_reached)
#endregion


#region Frame Tick & Input Dispatch
## 推进一帧 3D 漫步移动、热点邻近判定、地面光环高亮、镜头跟随及 2D 气泡屏幕投影。
func physics_tick(delta: float) -> void:
	if not _bound or _service == null or _actor == null:
		return

	var yaw_input: float = 0.0
	if Input.is_physical_key_pressed(KEY_Q):
		yaw_input -= 1.0
	if Input.is_physical_key_pressed(KEY_R):
		yaw_input += 1.0
	if absf(yaw_input) > 0.01 and _camera_rig != null:
		_camera_rig.nudge_yaw(yaw_input * 38.0 * delta)

	var manual_dir := _read_manual_move_vector()
	var moved_manually: bool = _actor.step_actor_motion(delta, manual_dir)
	if moved_manually and (
		_service.state.active_hotspot_id != OtomeTerraceConfig.HotspotId.NONE
		or _service.state.is_closeup_camera
	):
		_service.exit_hotspot_interaction_if_active()
		_actor.stop_interaction_loop()

	var near_id: int = _service.update_proximity(_actor.global_position)
	if _stage != null:
		var highlight_id: int = (
			_service.state.active_hotspot_id
			if _service.state.active_hotspot_id != OtomeTerraceConfig.HotspotId.NONE
			else near_id
		)
		_stage.highlight_hotspot_ring(highlight_id)

	if _camera_rig != null:
		_camera_rig.step_camera_follow(delta, _actor.global_position)
		_project_and_update_bubbles(near_id)


## 处理未被 HUD 按钮消费的 3D 世界点击漫步、视角拖拽与快捷键。
func handle_unhandled_input(event: InputEvent) -> void:
	if not _bound or _service == null:
		return

	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_right_dragging = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed and _camera_rig != null:
			_camera_rig.adjust_roam_zoom(-0.45)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed and _camera_rig != null:
			_camera_rig.adjust_roam_zoom(0.45)
		elif mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and _camera_rig != null and _actor != null:
			var hit_pos: Vector3 = _camera_rig.raycast_ground_plane(mb.position)
			if hit_pos.is_finite():
				if _service.state.active_hotspot_id != OtomeTerraceConfig.HotspotId.NONE or _service.state.is_closeup_camera:
					_service.exit_hotspot_interaction_if_active()
					_actor.stop_interaction_loop()
				_actor.set_walk_target(hit_pos, OtomeTerraceConfig.HotspotId.NONE)
		return

	if event is InputEventMouseMotion and _right_dragging and _camera_rig != null:
		var mm: InputEventMouseMotion = event as InputEventMouseMotion
		_camera_rig.nudge_yaw(-mm.relative.x * 0.16)
		return

	if event is InputEventKey:
		var key_ev: InputEventKey = event as InputEventKey
		if not key_ev.pressed or key_ev.echo:
			return
		match key_ev.physical_keycode:
			KEY_1:
				_on_outfit_cycle_requested()
			KEY_2:
				_on_expr_cycle_requested()
			KEY_G:
				_on_greet_requested()
			KEY_E, KEY_SPACE, KEY_ENTER:
				_on_interact_pill_requested()
			KEY_L:
				_on_weather_toggle_requested()
			KEY_C, KEY_ESCAPE:
				_on_camera_toggle_requested()
#endregion


#region Public Test & Showcase Helpers
## 直接瞬移并进入指定热点的浪漫特写交互（供自动化预览截图与冒烟测试调用）。
func enter_hotspot_immediately(hotspot_id: int) -> void:
	if _actor == null or hotspot_id < 0 or hotspot_id >= OtomeTerraceConfig.HOTSPOT_STAND_POSITIONS.size():
		return
	_actor.clear_walk_target()
	_actor.global_position = OtomeTerraceConfig.HOTSPOT_STAND_POSITIONS[hotspot_id]
	_activate_hotspot_interaction(hotspot_id)
	if _camera_rig != null:
		for _i: int in range(24):
			_camera_rig.step_camera_follow(0.1, _actor.global_position)
#endregion


#region Internal Interaction Handlers
func _read_manual_move_vector() -> Vector2:
	var x_axis: float = 0.0
	var z_axis: float = 0.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		x_axis -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		x_axis += 1.0
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		z_axis -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		z_axis += 1.0
	return Vector2(x_axis, z_axis)


func _on_hotspot_requested(hotspot_id: int) -> void:
	if _actor == null or _service == null:
		return
	if hotspot_id < 0 or hotspot_id >= OtomeTerraceConfig.HOTSPOT_STAND_POSITIONS.size():
		return

	var stand_pos: Vector3 = OtomeTerraceConfig.HOTSPOT_STAND_POSITIONS[hotspot_id]
	var flat_dist: float = Vector2(
		_actor.global_position.x - stand_pos.x,
		_actor.global_position.z - stand_pos.z
	).length()

	if flat_dist <= 0.62:
		_actor.global_position = stand_pos
		_activate_hotspot_interaction(hotspot_id)
	else:
		if _service.state.active_hotspot_id != OtomeTerraceConfig.HotspotId.NONE or _service.state.is_closeup_camera:
			_service.exit_hotspot_interaction_if_active()
		_service.state.status_badge_text = "漫步前往 · %s" % OtomeTerraceConfig.HOTSPOT_TITLES[hotspot_id]
		_service.state.notify_changed()
		_actor.set_walk_target(stand_pos, hotspot_id)


func _on_actor_walk_target_reached(pending_hotspot_id: int) -> void:
	if pending_hotspot_id >= 0:
		_activate_hotspot_interaction(pending_hotspot_id)


func _activate_hotspot_interaction(hotspot_id: int) -> void:
	if _service == null or _actor == null:
		return
	var ok: bool = _service.begin_hotspot_interaction(hotspot_id)
	if not ok:
		return
	var face_right: bool = hotspot_id != OtomeTerraceConfig.HotspotId.LAKESIDE_FOUNTAIN
	_actor.play_interaction_loop(OtomeTerraceConfig.HOTSPOT_ANIMS[hotspot_id], face_right)


func _on_outfit_cycle_requested() -> void:
	if _service != null:
		_service.cycle_outfit(1)


func _on_expr_cycle_requested() -> void:
	if _service != null:
		_service.cycle_expression(1)


func _on_greet_requested() -> void:
	if _service == null or _actor == null:
		return
	_service.trigger_greeting()
	_actor.play_greeting_once()


func _on_interact_pill_requested() -> void:
	if _service == null or _actor == null:
		return
	if _service.state.active_hotspot_id != OtomeTerraceConfig.HotspotId.NONE:
		_service.exit_hotspot_interaction_if_active()
		_actor.stop_interaction_loop()
		return

	var target_spot: int = _service.state.nearby_hotspot_id
	if target_spot == OtomeTerraceConfig.HotspotId.NONE:
		target_spot = _find_nearest_hotspot(_actor.global_position)
	_on_hotspot_requested(target_spot)


func _on_weather_toggle_requested() -> void:
	if _service != null:
		_service.toggle_weather_mode()


func _on_camera_toggle_requested() -> void:
	if _service == null or _actor == null:
		return
	var now_closeup: bool = _service.toggle_closeup_camera()
	if not now_closeup:
		_actor.stop_interaction_loop()


func _on_choice_selected(choice_index: int) -> void:
	if _service != null:
		_service.choose_dialogue_option(choice_index)


func _on_state_changed() -> void:
	_sync_all_visuals(true)


func _sync_all_visuals(animate_skin_pop: bool) -> void:
	if _service == null or _service.state == null:
		return
	var st: OtomeTerraceState = _service.state

	if _actor != null:
		_actor.apply_otome_skins(
			st.get_outfit_skin(),
			st.get_expr_skin(),
			st.prop_skin,
			animate_skin_pop
		)
	if _stage != null:
		_stage.apply_weather_mode(st.weather_mode)
	if _camera_rig != null:
		_camera_rig.set_closeup_mode(st.is_closeup_camera)
	if _view != null:
		_view.render_state(st)


func _project_and_update_bubbles(nearby_id: int) -> void:
	if _view == null or _camera_rig == null or _service == null:
		return
	var anchors: Array[Vector3] = OtomeTerraceConfig.HOTSPOT_BUBBLE_ANCHORS
	var count: int = mini(_screen_anchors_buf.size(), anchors.size())
	for i: int in range(count):
		_screen_anchors_buf[i] = _camera_rig.project_world_to_screen(anchors[i])
	var hide_bubbles: bool = _service.state.is_closeup_camera
	_view.update_hotspot_bubbles(_screen_anchors_buf, nearby_id, hide_bubbles)


func _find_nearest_hotspot(actor_pos: Vector3) -> int:
	var best_idx: int = 0
	var best_d2: float = INF
	for i: int in range(OtomeTerraceConfig.HOTSPOT_STAND_POSITIONS.size()):
		var sp: Vector3 = OtomeTerraceConfig.HOTSPOT_STAND_POSITIONS[i]
		var dx: float = actor_pos.x - sp.x
		var dz: float = actor_pos.z - sp.z
		var d2: float = dx * dx + dz * dz
		if d2 < best_d2:
			best_d2 = d2
			best_idx = i
	return best_idx
#endregion
