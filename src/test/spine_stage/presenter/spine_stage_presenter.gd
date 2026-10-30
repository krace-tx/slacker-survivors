class_name SpineStagePresenter
extends RefCounted

## 2.5D「方案 B」舞台业务协调器（MSVP Presenter，胶合键鼠输入、领域服务、3D 角色与 HUD 视图）。[br]
##
## [b]核心职责：[/b][br]
## 1. 监听 [SpineStageView] 信号与键鼠快捷键（[code]WASD[/code] 走位、[code]Space[/code] 跳跃、[code]J/左键[/code] 连斩、[code]1-3[/code] 换武器、[code]Q/E/4-6[/code] 换套装、[code]L[/code] 切光影）；[br]
## 2. 驱动 [SpineActor3D] 物理运动与实时多皮肤热切（[method SpineActor3D.apply_loadout_skins]）；[br]
## 3. 在挥砍命中帧调用 [SpineStageService] 执行零开方扇形受击裁决，联动稻草魔像受击闪白与相机微震屏。

#region Private Dependencies & State
var _service: SpineStageService = null
var _view: SpineStageView = null
var _stage: SpineCourtyardStage3D = null
var _camera_rig: SpineCameraRig3D = null
var _player_actor: SpineActor3D = null
var _dummies: Array[SpineActor3D] = []
var _dummy_homes: Array[Vector3] = []

var _jump_queued: bool = false
var _bound: bool = false
#endregion


#region Lifecycle
func _init(
	service: SpineStageService,
	view: SpineStageView,
	stage: SpineCourtyardStage3D,
	camera_rig: SpineCameraRig3D,
	player_actor: SpineActor3D,
	dummies: Array[SpineActor3D],
	dummy_homes: Array[Vector3]
) -> void:
	_service = service
	_view = view
	_stage = stage
	_camera_rig = camera_rig
	_player_actor = player_actor
	_dummies = dummies
	_dummy_homes = dummy_homes


## 建立全部信号订阅并执行首帧状态同步。
func bind() -> void:
	if _bound or _service == null:
		return
	_bound = true

	_service.state.state_changed.connect(_on_state_changed)
	if _view != null:
		_view.weapon_selected.connect(_on_weapon_selected)
		_view.outfit_selected.connect(_on_outfit_selected)
		_view.lighting_toggle_requested.connect(_on_lighting_toggle_requested)
	if _player_actor != null:
		_player_actor.attack_hit_frame_reached.connect(_on_player_attack_hit_frame)

	_sync_loadout_to_actor(false)
	if _stage != null:
		_stage.apply_lighting_mode(_service.state.lighting_mode)
	_on_state_changed()


## 解除全部信号订阅并清空场景节点引用，防止闭包悬挂。
func dispose() -> void:
	if _bound and _service != null:
		if _service.state.state_changed.is_connected(_on_state_changed):
			_service.state.state_changed.disconnect(_on_state_changed)
		if _view != null:
			if _view.weapon_selected.is_connected(_on_weapon_selected):
				_view.weapon_selected.disconnect(_on_weapon_selected)
			if _view.outfit_selected.is_connected(_on_outfit_selected):
				_view.outfit_selected.disconnect(_on_outfit_selected)
			if _view.lighting_toggle_requested.is_connected(_on_lighting_toggle_requested):
				_view.lighting_toggle_requested.disconnect(_on_lighting_toggle_requested)
		if _player_actor != null and _player_actor.attack_hit_frame_reached.is_connected(_on_player_attack_hit_frame):
			_player_actor.attack_hit_frame_reached.disconnect(_on_player_attack_hit_frame)

	_bound = false
	_view = null
	_stage = null
	_camera_rig = null
	_player_actor = null
	_dummies.clear()
	_dummy_homes.clear()
#endregion


#region Per-Frame Simulation & Input
## 推进一帧 3D 物理走位、稻草魔像回弹与平滑相机追踪。
func physics_tick(delta: float) -> void:
	if not _bound or _player_actor == null or _service == null:
		return

	var move_xz: Vector2 = _sample_move_input()
	var want_jump: bool = _jump_queued
	_jump_queued = false
	if want_jump and _player_actor.is_on_floor():
		_service.notify_jump_triggered()

	var status_label: String = _player_actor.step_hero_motion(
		delta,
		move_xz,
		_service.get_effective_move_speed(),
		want_jump
	)
	_service.update_action_label(status_label)

	var dummy_count: int = mini(_dummies.size(), _dummy_homes.size())
	for i: int in range(dummy_count):
		var dummy: SpineActor3D = _dummies[i]
		if dummy != null:
			dummy.step_dummy_motion(delta, _dummy_homes[i])

	if _camera_rig != null:
		_camera_rig.tick_follow(delta, _player_actor.global_position)


## 处理未被 HUD 消费的键盘与鼠标输入。
func handle_unhandled_input(event: InputEvent) -> void:
	if not _bound or _service == null:
		return

	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			trigger_melee_attack()
		return

	if not (event is InputEventKey):
		return
	var key_ev: InputEventKey = event as InputEventKey
	if not key_ev.pressed or key_ev.echo:
		return

	match key_ev.physical_keycode:
		KEY_SPACE:
			_jump_queued = true
		KEY_J, KEY_K:
			trigger_melee_attack()
		KEY_1:
			_on_weapon_selected(0)
		KEY_2:
			_on_weapon_selected(1)
		KEY_3:
			_on_weapon_selected(2)
		KEY_4:
			_on_outfit_selected(0)
		KEY_5:
			_on_outfit_selected(1)
		KEY_6:
			_on_outfit_selected(2)
		KEY_Q:
			_on_cycle_outfit(-1)
		KEY_E:
			_on_cycle_outfit(1)
		KEY_L:
			_on_lighting_toggle_requested()
#endregion


#region Public Action Entrypoints (Also Used by Headless Smoke Tests)
## 主动触发一次主角近战挥砍。
func trigger_melee_attack() -> int:
	if _player_actor == null or _service == null:
		return 0
	var step: int = _player_actor.trigger_attack()
	if step > 0:
		_service.notify_attack_started(step)
	return step


## 切换至指定武器槽位并同步刷新主角 Spine 皮肤。
func select_weapon_slot(index: int) -> void:
	_on_weapon_selected(index)


## 切换至指定服饰套装槽位并同步刷新主角 Spine 皮肤。
func select_outfit_slot(index: int) -> void:
	_on_outfit_selected(index)
#endregion


#region Internal Handlers
func _sample_move_input() -> Vector2:
	var rx: float = 0.0
	var rz: float = 0.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		rx += 1.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		rx -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		rz += 1.0
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		rz -= 1.0
	var vec := Vector2(rx, rz)
	if vec.length_squared() > 1.0:
		vec = vec.normalized()
	return vec


func _on_weapon_selected(index: int) -> void:
	if _service != null and _service.select_weapon(index, true):
		_sync_loadout_to_actor(true)


func _on_outfit_selected(index: int) -> void:
	if _service != null and _service.select_outfit(index, true):
		_sync_loadout_to_actor(true)


func _on_cycle_outfit(step: int) -> void:
	if _service != null:
		_service.cycle_outfit(step)
		_sync_loadout_to_actor(true)


func _on_lighting_toggle_requested() -> void:
	if _service == null:
		return
	var next_mode: int = _service.toggle_lighting_mode()
	if _stage != null:
		_stage.apply_lighting_mode(next_mode)


func _sync_loadout_to_actor(animate_pop: bool) -> void:
	if _player_actor == null or _service == null:
		return
	var w_skin: String = SpineStageConfig.get_weapon_skin(_service.state.weapon_index)
	var o_skin: String = SpineStageConfig.get_outfit_skin(_service.state.outfit_index)
	_player_actor.apply_loadout_skins(w_skin, o_skin, animate_pop)


func _on_player_attack_hit_frame(combo_step: int) -> void:
	if _player_actor == null or _service == null:
		return
	var dummy_positions: Array[Vector3] = []
	for dummy: SpineActor3D in _dummies:
		if dummy != null:
			dummy_positions.append(dummy.global_position)
		else:
			dummy_positions.append(Vector3(9999.0, 0.0, 9999.0))

	var hit_indices: Array[int] = _service.evaluate_melee_hits(
		_player_actor.global_position,
		_player_actor.is_facing_right(),
		dummy_positions,
		combo_step
	)
	for hit_idx: int in hit_indices:
		if hit_idx >= 0 and hit_idx < _dummies.size():
			var hit_dummy: SpineActor3D = _dummies[hit_idx]
			if hit_dummy != null:
				hit_dummy.apply_dummy_hit_reaction(_player_actor.global_position)
	if not hit_indices.is_empty() and _camera_rig != null:
		_camera_rig.add_trauma(0.36 if combo_step == 1 else 0.52)


func _on_state_changed() -> void:
	if _view != null and _service != null:
		_view.render_state(_service.state)
#endregion
